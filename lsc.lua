--- Library for symbolic computation
local lsc = {}

--- Converts various data types into nodes
---@param ... any The values to convert
---@return table ... All the converted nodes
lsc.convert = function (...)
    local result = {}

    for _, x in ipairs({...}) do
        if lsc.isNode(x) then
            table.insert(result, x:copy())
        elseif type(x) == "number" then
            table.insert(result, lsc.Node('number', x))
        elseif type(x) == "string" then
            table.insert(result, lsc.Node('symbol', x))
        else
            error("Cannot convert " .. x .. ", a'" .. type(x) .. "', to a node.")
        end
    end

    return (unpack or table.unpack)(result)
end

--- Performs numerical operations between two number nodes
---@param opp string The operation to perform ("sum" or "prod")
---@param x table The first number node
---@param y table The second number node
---@return table|nil Result node or nil if operation not applicable
local computeNumber = function (opp, x, y)
    if opp == "sum" then
        return lsc.Node('number', x.leaf + y.leaf)
    elseif opp == "prod" and not (x.inverse or y.inverse) then
        return lsc.Node('number', x.leaf * y.leaf)
    end
end

--- Finds common factors between two non-terminal nodes
---@param x table First non-terminal node
---@param y table Second non-terminal node
---@return table common Common factors
---@return table diffx Factors unique to x
---@return table diffy Factors unique to y
local findCommon = function (x, y)
    assert(not x:isTerminal())
    assert(not y:isTerminal())
    
    x = x:copy()
    y = y:copy()

    local xpos = 1
    local ypos = 1
    local common = {}
    local diffx  = x.children
    local diffy  = y.children

    while xpos <= #diffx do
        local xchild = diffx[xpos]
        local ychild = diffy[ypos]

        if xchild:isEqual(ychild) then
            table.insert(common, xchild)
            table.remove(diffx, xpos)
            table.remove(diffy, ypos)
        else
            ypos = ypos+1
        end

        if ypos > #diffy then
            xpos = xpos + 1
            ypos = 1
        end
    end

    return common, diffx, diffy
end

--- Factors out common terms in a sum of products
---@param x table First product node
---@param y table Second product node
---@return table|nil The factored expression or nil if no common factors
local computeAddFactors = function (x, y)
    local common, diffx, diffy = findCommon(x, y)

    local k = lsc.Node('prod', common)

    if #diffx == 0 then
        diffx = {lsc.Node('number', 1)}
    end
    if #diffy == 0 then
        diffy = {lsc.Node('number', 1)}
    end

    if #common == 0 then
        return
    end

    local p = lsc.Node('sum', {
        lsc.Node('prod', diffx),
        lsc.Node('prod', diffy)
    })

    local rp = p:reduce()

    -- Only apply factorization if it simplifies the expression
    if rp:getSize() < p:getSize() then
        return lsc.Node('prod', {
            rp,
            k
        }):reduce()
    end
end

--- Try to computes nodes
---@param opp string The operation ("sum" or "prod")
---@param x any The first operand 
---@param y any The second operand
---@return table The resulting node
lsc.compute = function(opp, x, y)
    x, y = lsc.convert(x, y)

    -- Try numeric computation if both are numbers
    if x.type == "number" and y.type == "number" then
        local result = computeNumber(opp, x, y)
        if result then
            return result
        end
    end

    if opp == "sum" then
        local xx = x
        local yy = y

        -- Handle special cases for addition
        if x:isTerminal() and y:isTerminal() then
            if x:isEqual(y) then
                -- If adding identical terms, convert to 2*term
                return lsc.Node('prod', {
                    lsc.Node('number', 2),
                    x
                })
            end
        elseif x:isTerminal() then
            -- Convert terminal to product for factor analysis
            xx = lsc.Node('prod', {
                lsc.Node('number', 1),
                x
            })
        elseif y:isTerminal() then
            -- Convert terminal to product for factor analysis
            yy = lsc.Node('prod', {
                lsc.Node('number', 1),
                y
            })
        end

        -- Try to factor out common terms
        if xx.type == "prod" and yy.type == "prod" then
            local result = computeAddFactors(xx, yy)

            if result then
                return result
            end
        end
    end

    -- Default: create a new operation node
    return lsc.Node(opp, {x, y})
end

--- Creates a negation of a node
---@param x table The node to negate
---@return table The negated node
lsc.neg = function (x)
    if x.type == "number" then
        return lsc.Node('number', x.leaf * -1)
    else
        return lsc.Node('prod', {
            lsc.Node('number', -1),
            x
        })
    end
end

--- Used to define node metatable opperations
---@param name string The operation name
---@param infos table|nil Optional behavior configuration
---@return function The operation function
local __opp = function(name, infos)
    return function (x, y)
        infos = infos or {}
        infos.left = infos.left or {}
        infos.right = infos.right or {}

        x, y = lsc.convert(x, y)

        if infos.left.negative then
            x = lsc.neg(x)
        end
        if infos.right.negative then
            y = lsc.neg(y)
        end

        if infos.unary then
            return x
        end

        -- Handle different combination cases
        if x:isTerminal() and y:isTerminal() then
            return lsc.Node(name, {x, y})
        elseif x:isTerminal() and y.type == name then
            y:prepend(x)
            return y
        elseif y:isTerminal() and x.type == name then
            x:append(y)
            return x
        elseif x.type == name and y.type == name then
            x:extend(y.children)
            return x
        else
            return lsc.Node(name, {x, y})
        end
    end
end

--- Metatable for Node objects with operators and methods
lsc.mtNode = {
    __add = __opp("sum"),
    __sub = __opp("sum", {right={negative=true}}),
    __unm = __opp(nil, {left={negative=true}, unary=true}),
    __mul = __opp("prod"),
    __div = __opp("prod", {right={inverse=true}}),

    --- Converts a node to a string representation
    __tostring = function (self)
        if self:isTerminal() then
            local s = tostring(self.leaf)
            return s
        end

        local result = {}
        for _, child in ipairs(self.children) do
            local s = tostring(child)
            -- Add parentheses around sum inside product
            if self.type == "prod" and child.type == "sum" then
                s = "(" .. s .. ")"
            end
            table.insert(result, s)
        end

        local join
        if self.type == "sum" then
            join = " + "
        elseif self.type == "prod" then
            join = " * "
        end

        local finalResult = table.concat(result, join)

        -- Clean up representation for better readability
        finalResult = finalResult:gsub('%-1 %* ', '-')
        finalResult = finalResult:gsub('+ %-', '- ')

        return finalResult
    end,

    __index = {
        --- Checks if a node is a terminal (leaf) node
        ---@return boolean True if terminal, false otherwise
        isTerminal = function (self)
            return self.leaf and true
        end,

        --- Creates a deep copy of the node
        ---@return table New copy of the node
        copy = function (self)
            if self:isTerminal() then
                return lsc.Node(self.type, self.leaf, self.negative, self.inverse)
            end

            local children = {}
            for i, child in ipairs(self.children) do
                children[i] = child:copy()
            end

            return lsc.Node(self.type, children, self.negative, self.inverse)
        end,

        --- Adds a node to the beginning of children
        ---@param x table The node to prepend
        prepend = function (self, x)
            if x.type == self.type then
                for i, child in ipairs(x.children) do
                    table.insert(self.children, i, child)
                end
            else
                table.insert(self.children, 1, x)
            end
        end,

        --- Adds a node to the end of children
        ---@param x table The node to append
        append = function (self, x)
            if x.type == self.type then
                self:extend(x.children)
            else
                table.insert(self.children, x)
            end
        end,

        --- Appends all nodes from a table
        ---@param t table Table of nodes to append
        extend = function (self, t)
            for _, x in ipairs(t) do
                self:append(x)
            end
        end,

        --- Calculates the size of the node tree
        ---@return number The size of the node
        getSize = function (self)
            if self:isTerminal() then
                if self.type == "symbol" then
                    return 1000
                else
                    return 1
                end
            end

            local result = 1
            for _, child in ipairs(self.children) do
                result = result + child:getSize()
            end

            return result
        end,

        --- Simplifies a node by reducing its children
        ---@return table The reduced node
        reduce = function (self)
            if self:isTerminal() then
                return self
            end

            local children = {}

            -- First reduce all children
            for i, child in ipairs(self.children) do
                children[i] = child:reduce()
            end

            local pos1 = 1
            local pos2 = 2

            -- Combine children pairwise when possible
            while pos2 <= #children do
                local x = children[pos1]
                local y = children[pos2]

                local z  = lsc.Node(self.type, {x, y})
                local zr = lsc.compute(self.type, x, y)

                -- Replace with reduced form if it's smaller
                if z:getSize() > zr:getSize() then
                    children[pos1] = zr
                    table.remove(children, pos2)
                else
                    pos2 = pos2+1
                end

                if pos2 > #children then
                    pos1 = pos1+1
                    pos2 = pos1+1
                end
            end

            return lsc.Node(self.type, children)
        end,

        --- Checks if two nodes are equal
        ---@param y table The node to compare with
        ---@return boolean True if nodes are equal
        isEqual = function (self, y)
            local x = self:reduce()
            y = y:reduce()

            if x.type ~= y.type then
                return false
            end

            if x:isTerminal() and y:isTerminal() then
                return x.leaf == y.leaf
            elseif x:isTerminal() or y:isTerminal() then
                return false
            end

            local xx = x:copy()
            local yy = y:copy()

            -- Compare children in any order
            local ypos = 1
            while true do
                if xx.children[1]:isEqual(yy.children[ypos]) then
                    table.remove(xx.children, 1)
                    table.remove(yy.children, ypos)
                    ypos = 1
                else
                    ypos = ypos+1
                end
                
                if #xx.children == 0 or #yy.children == 0 then
                    break
                end

                if ypos > #yy.children then
                    return false
                end
            end

            return #xx.children == 0 and #yy.children == 0
        end
    }
}

--- Creates a new node of specified type with given children
---@param nodeType string The type of node to create ("number", "symbol", "sum", "prod")
---@param children any Children for the node (table for composite nodes, value for terminals)
---@return table The created node
lsc.Node = function (nodeType, children)
    local node = setmetatable({}, lsc.mtNode)
    node.type = nodeType

    if type(children) == "table" then
        -- Simplify single-child operations
        if (nodeType == "sum" or nodeType == "prod") and #children == 1 then
            return children[1]
        end

        node.children = {}
        for _, child in ipairs(children) do
            node:append(child)
        end
    else
        node.leaf = children
    end

    return node
end

--- Checks if an item is a node
---@param item any The item to check
---@return boolean True if item is a node
lsc.isNode = function (item)
    return type(item) == "table" and getmetatable(item) == lsc.mtNode
end

--- Pretty-prints a node tree for debugging
---@param item table The node to inspect
---@param indent string|nil Current indentation level
---@return string The formatted string representation
lsc.inspect = function (item, indent)
    indent = indent or ""
    local result = {indent, item.type, " :"}

    if item:isTerminal() then
        table.insert(result, "  ")
        table.insert(result, tostring(item))
    else
        for _, child in ipairs(item.children) do
            table.insert(result, "\n")
            table.insert(result, lsc.inspect(child, "\t"..indent))
        end
    end

    return table.concat(result)
end

return lsc
