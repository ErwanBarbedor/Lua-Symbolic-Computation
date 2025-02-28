local lsc = require "lsc"

local tests = {
    -- print
    {"x",       {}, "x"},
    {"x+1",     {}, "x + 1"},
    {"1+x",     {}, "1 + x"},
    {"2*x-x",   {}, "2 * x - x"},
    {"2*(x+1)", {}, "2 * (x + 1)"},


    --=== Reduction ===--
    {"x",   {"reduce"}, "x"},
    {"2*x", {"reduce"}, "2 * x"},

    -- simple computation
    {"x+1+1",             {"reduce"}, "x + 2"},
    {"x+1*3",             {"reduce"}, "x + 3"},
    {"x-1*3",             {"reduce"}, "x - 3"},
    {"1+x+1",             {"reduce"}, "2 + x"},
    {"x+1-1",             {"reduce"}, "x + 0"},
    {"1+x+y+2-z-4",       {"reduce"}, "-1 + x + y - z"},
    {"-2*3 + x + 5*(-2)", {"reduce"}, "-16 + x"},
    {"1+(x+1)",           {"reduce"}, "2 + x"},
    {"1+2*(1+x+1)",       {"reduce"}, "1 + 2 * (2 + x)"},

    -- factorisation reduction
    {"x+x",              {"reduce"}, "2 * x"},
    {"x+2*x",            {"reduce"}, "3 * x"},
    {"2*x+x",            {"reduce"}, "3 * x"},
    {"2*x+3*x",          {"reduce"}, "5 * x"},
    {"2*x-x*3",          {"reduce"}, "-x"},
    {"2*x+y-x*3",        {"reduce"}, "-x + y"},
    {"2*(x+1)-3*(x+1)",  {"reduce"}, "-(x + 1)"},
    {"5*x+y-3*y+x*(-2)", {"reduce"}, "3 * x - 2 * y"},

    --=== expand ===
    -- {"2*(x+2)", {"expand"}, "2 * x + 2 * 2"},
}

local env = {
    lsc = lsc,
    x = lsc.convert("x"),
    y = lsc.convert("y"),
    z = lsc.convert("z"),
}

for _, test in ipairs(tests) do
    local input = test[1]
    local transforms = test[2]
    local output = test[3]

    local loadInput, err = load("return " .. input, nil, nil, env)
    
    if loadInput then
        sucess, result = pcall(loadInput)

        if sucess then
            for _, t in ipairs(transforms) do
                result = result[t](result)
            end
        end
    else
        result = err
    end

    result = tostring(result)

    if result ~= output then
        print("For test '" .. input .. "', expected '" .. output .. "', but obtained '" .. result .. "'.")
    end
end