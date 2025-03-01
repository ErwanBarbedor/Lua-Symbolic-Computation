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
---@return table common Common factors found in both nodes
---@return table diffx Factors unique to x after removing common factors
---@return table diffy Factors unique to y after removing common factors
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

    -- Compare each child in x with each child in y
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

        -- If we've checked all children in y, move to next child in x
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

    -- If all terms were common, replace with 1
    if #diffx == 0 then
        diffx = {lsc.Node('number', 1)}
    end
    if #diffy == 0 then
        diffy = {lsc.Node('number', 1)}
    end

    -- If no common factors were found, return nil
    if #common == 0 then
        return
    end

    -- Create new expression in factored form: (diffx + diffy) * common
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

--- Attempts to factor out common base in power expressions
---@param x table First power node
---@param y table Second power node
---@return table|nil The factored expression or nil if not applicable
local computeMulFactors = function (x, y)
    local common, diffx, diffy = findCommon(x, y)

    -- Only factor if both have the same base
    if not x.children[1]:isEqual(y.children[1]) then return end

    local base = x.children[1]
    local e1   = x.children[2]
    local e2   = y.children[2]
    
    -- Create expression like base^(e1+e2)
    local p = lsc.Node('sum', {
        e1,
        e2
    })

    local rp = p:reduce()

    -- Only apply if it simplifies the expression
    if rp:getSize() < p:getSize() then
        return lsc.Node('pow', {
            base,
            rp
        })
    end
end

--- Attempts to factorize or simplify expressions with common terms
---@param opp string Operation type ("prod" or "pow")
---@param x table First node
---@param y table Second node
---@return table|nil Simplified node or nil if no simplification possible
local factorizeReduce = function (opp, x, y)
    -- Handle case where both operands are identical
    if x.type ~= opp and y.type ~= opp then
        if x:isEqual(y) then
            if opp == "prod" then
                return lsc.Node(opp, {
                    lsc.Node('number', 2),
                    x
                })
            else
                return lsc.Node(opp, {
                    x,
                    lsc.Node('number', 2),
                })
            end
        end
    -- Convert single operands to operation nodes for uniform handling
    elseif x.type ~= opp then
        x = lsc.Node(opp, {
            x,
            lsc.Node('number', 1),
            
        })
    elseif y.type ~= opp then
        y = lsc.Node(opp, {
            y,
            lsc.Node('number', 1),
            
        })
    end

    -- Apply factorization when both terms are of the same operation type
    if x.type == opp and y.type == opp then
        local result

        if opp == "prod" then
            result = computeAddFactors(x, y)
        elseif opp == "pow" then
            result = computeMulFactors(x, y)
        end

        if result then
            return result
        end
    end
end

--- Expands a product containing a sum (distributive property)
---@param node table The product node to expand
---@return table The expanded expression
local function expandProd (node)
    local sumElement
    local otherElements = {}

    -- Look for a sum in the product
    for _, child in ipairs(node.children) do
        if not sumElement and child.type == "sum" then
            sumElement = child
        else
            table.insert(otherElements, child)
        end
    end

    -- If no sum found, no expansion needed
    if not sumElement then
        return node
    end

    -- Apply distributive property: a*(b+c) = a*b + a*c
    local result = lsc.Node('sum')

    for _, child in ipairs(sumElement.children) do
        result:append(lsc.Node('prod', {
            lsc.Node('prod', otherElements),
            child
        }):expand())
    end

    return result
end

--- Expands a power expression when exponent is a positive integer
---@param node table The power node to expand
---@return table The expanded expression
local function expandPow (node)
    local base = node.children[1]
    local pow  = node.children[2]

    -- Only expand if exponent is a whole number
    if pow.type ~= "number" or math.floor(pow.leaf) ~= pow.leaf then
        return node
    end

    -- Create a product of the base repeated pow times
    local result = lsc.Node('prod')

    for i=1, pow.leaf do
        result:append(base:copy())
    end

    -- Further expand any products in the result
    return expandProd(result)
end

--- Performs computations between nodes, with various optimizations
---@param opp string The operation ("sum", "prod", or "pow")
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

    -- Handle special cases for identity and zero elements
    if (x:isEqual(0) or y:isEqual(0)) and opp == "prod" then
        return lsc.Node('number', 0)
    elseif x:isEqual(0) and opp == "sum" then
        return y
    elseif (x:isEqual(0) or x:isEqual(1)) and opp == "pow" then
        return x
    elseif y:isEqual(0) and opp == "sum" then
        return x
    elseif y:isEqual(0) and opp == "pow" then
        return lsc.Node('number', 1)
    elseif x:isEqual(1) and opp == "prod" then
        return y
    elseif y:isEqual(1) and opp == "prod" then
        return x
    elseif y:isEqual(1) and opp == "pow" then
        return x
    end

    -- Try factorization for more complex expressions
    if opp == "sum" then
        local result = factorizeReduce("prod", x, y)
        if result then
            return result
        end
    elseif opp == "prod" then
        local result = factorizeReduce("pow", x, y)
        if result then
            return result
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

--- Used to define node metatable operations
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

    --- Power operation for nodes
    ---@param x table Base node
    ---@param y table Exponent node
    ---@return table Power expression node
    __pow = function (x, y)
        x, y = lsc.convert(x, y)
        return lsc.Node('pow', {x, y})
    end,

    --- Converts a node to a string representation
    ---@param self table The node to convert to string
    ---@return string String representation of the node
    __tostring = function (self)
        if self:isTerminal() then
            local s = tostring(self.leaf)
            return s
        end

        local bjoin
        if self.type == "sum" then
            bjoin = " + "
        elseif self.type == "prod" then
            bjoin = " * "
        elseif self.type == "pow" then
            bjoin = "^"
        end

        local result = {}
        for i, child in ipairs(self.children) do
            local s = tostring(child)
            -- Add parentheses around sum inside product
            local addp
            if (self.type == "prod" and child.type == "sum") then
                addp = true
            elseif self.type == "pow" and not child:isTerminal() then
                addp = true
            elseif self.type == "prod" and child.type == "number" and child.leaf < 0 and i>1 then
                addp = true
            end

            if addp then
                s = "(" .. s .. ")"
            end

            local join = bjoin
            local insertjoin = false
            if i<#self.children then
                insertjoin = true
                local nchild = self.children[i+1]
                
                -- Special formatting for multiplication
                if self.type == "prod" then
                    if child.type == "number" and nchild.type ~= "number" and child.leaf ~= 1 then
                        insertjoin = false
                        if child.leaf == -1 then
                            s = "-"
                        end
                    elseif child.type ~= "number" and nchild.type ~= "number" and not child:isEqual(nchild) then
                        insertjoin = false
                    end
                -- Special formatting for addition with negative numbers
                elseif self.type == "sum" then
                    if nchild.type == "number" and nchild.leaf < 0 then
                        join = " - "
                    elseif nchild.type == "prod" and nchild.children[1].type == "number" and nchild.children[1].leaf < 0 then
                        join = " - "
                    end
                end
            end

            -- Handle negative numbers in sums
            if i>1 then
                if self.type == "sum" then
                    local isneg = false
                    if child.type == "number" and child.leaf < 0 then
                        isneg = true
                    elseif child.type == "prod" and child.children[1].type == "number" and child.children[1].leaf < 0 then
                        isneg = true
                    end

                    if isneg then
                        s = s:gsub('%-', '', 1)
                    end
                end
            end

            table.insert(result, s)
            if insertjoin then
                table.insert(result, join)
            end
        end

        local finalResult = table.concat(result)

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
        ---@return number The size of the node (higher for symbols to prioritize numeric simplifications)
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

        --- Expands expressions using distributive property
        ---@return table The expanded node
        expand = function (self)
            if self:isTerminal() then
                return self
            end

            local children = {}

            for i, child in ipairs(self.children) do
                children[i] = child:expand()
            end

            local result = lsc.Node(self.type, children)

            if self.type == "prod" then
                return expandProd(result)
            elseif self.type == "pow" then
                return expandPow(result)
            else
                return result
            end
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
            y = lsc.convert(y)
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
---@param nodeType string The type of node to create ("number", "symbol", "sum", "prod", "pow")
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
    elseif children == nil then
        node.children = {}
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
