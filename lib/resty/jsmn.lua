local setmetatable = setmetatable
local ffi          = require "ffi"
local ffi_new      = ffi.new
local ffi_typeof   = ffi.typeof
local ffi_cdef     = ffi.cdef
local ffi_load     = ffi.load
local C            = ffi.C
local sub          = string.sub
local type         = type
local null         = {}
if ngx and ngx.null then
    null = ngx.null
end
ffi_cdef[[
typedef enum {
	JSMN_PRIMITIVE = 0,
	JSMN_OBJECT    = 1,
	JSMN_ARRAY     = 2,
	JSMN_STRING    = 3
} jsmntype_t;
typedef enum {
	JSMN_ERROR_NOMEM = -1,
	JSMN_ERROR_INVAL = -2,
	JSMN_ERROR_PART  = -3
} jsmnerr_t;
typedef struct {
	jsmntype_t type;
	int start;
	int end;
	int size;
    int parent;
} jsmntok_t;
typedef struct {
	unsigned int pos;
	unsigned int toknext;
	         int toksuper;
} jsmn_parser;
void jsmn_init(jsmn_parser *parser);
jsmnerr_t jsmn_parse(jsmn_parser *parser, const char *js, size_t len, jsmntok_t *tokens, unsigned int num_tokens);
]]
local arr = { __index = { __jsontype = "array"  }}
local obj = { __index = { __jsontype = "object" }}
local lib = ffi_load("libjsmn")
local ctx = ffi_typeof("jsmn_parser")
local tok = ffi_typeof("jsmntok_t[?]")
local ok, newtab = pcall(require, "table.new")
if not ok then newtab = function() return {} end end
local jsmn = newtab(0, 9)
jsmn.__index = jsmn
function jsmn.new()
    local self = newtab(1, 0)
    self[1] = ffi_new(ctx)
    return setmetatable(self, jsmn)
end
function jsmn:init()
    lib.jsmn_init(self[1])
end
function jsmn:parse(json, n)
    local l = #json
    if not n then
        n = tonumber(lib.jsmn_parse(self[1], json, l, nil, 0))
        self:init()
        if n < 1 then return nil, n end
    end
    local tokens = ffi_new(tok, n)
    local count = tonumber(lib.jsmn_parse(self[1], json, l, tokens, n))
    if count < 1 then return nil, count end
    return tokens, count
end
function jsmn.decode(json, l, m)
    if type(json) ~= "string" then return json, 1 end
    local ctx = ffi_new(ctx)
    lib.jsmn_init(ctx)
    if not l then l = #json end
    if not m then
        m = tonumber(lib.jsmn_parse(ctx, json, l, nil, 0))
        if m < 1 then return nil, m end
        lib.jsmn_init(ctx)
    end
    local tokens = ffi_new(tok, m)
    lib.jsmn_parse(ctx, json, l, tokens, m)
    local n, l, k = newtab(m, 0), m - 1, nil
    n[0] = setmetatable(newtab(0, tokens[0].size), obj)
    for i=1, l do
        local token = tokens[i]
        local t, s, e, z, p = token.type, token.start + 1, token["end"], token.size, n[token.parent]
        local j = getmetatable(p) == obj and k or #p + 1
        if t == C.JSMN_PRIMITIVE then
            n[i] = p
            local  c = sub(json, s, s)
            if     c == "f" then p[j] = false
            elseif c == "t" then p[j] = true
            elseif c == "n" then p[j] = null
            else                 p[j] = tonumber(sub(json, s, e)) end
        elseif t == C.JSMN_OBJECT then
            n[i] = setmetatable(newtab(0, z), obj)
            p[j] = n[i]
        elseif t == C.JSMN_ARRAY then
            n[i] = setmetatable(newtab(z, 0), arr)
            p[j] = n[i]
        elseif t == C.JSMN_STRING then
            n[i] = p
            local v = sub(json, s, e)
            if z == 1 then k = v else p[j] = v end
        end
    end
    return n[0], m
end
function jsmn.dec(json, tokens, current)
    local token = tokens[current]
    local t = token.type
    if t == C.JSMN_OBJECT then return jsmn.obj(json, tokens, current) end
    if t == C.JSMN_ARRAY  then return jsmn.arr(json, tokens, current) end
    if t == C.JSMN_PRIMITIVE then
        local s = token.start + 1
        local c = sub(json, s, s)
        if c == "f" then return false, current + 1 end
        if c == "t" then return true,  current + 1 end
        if c == "n" then return null,  current + 1 end
        return tonumber(sub(json, s, token["end"])), current + 1
    end
    return sub(json, token.start + 1, token["end"]), current + 1
end
function jsmn.arr(json, tokens, current)
    local token = tokens[current]
    local z = token.size
    local a = setmetatable(newtab(z, 0), arr)
    current = current + 1
    for i = 1, z do a[i], current = jsmn.dec(json, tokens, current) end
    return a, current
end
function jsmn.obj(json, tokens, current)
    local token = tokens[current]
    local z = token.size
    local o = setmetatable(newtab(0, z), obj)
    current = current + 1
    for i = 1, z do
        local k, c    = jsmn.dec(json, tokens, current)
        o[k], current = jsmn.dec(json, tokens, c)
    end
    return o, current
end
function jsmn.decode2(json, l, m)
    if type(json) ~= "string" then return json, 1 end
    local ctx = ffi_new(ctx)
    lib.jsmn_init(ctx)
    if not l then l = #json end
    if not m then
        m = tonumber(lib.jsmn_parse(ctx, json, l, nil, 0))
        if m < 1 then return nil, m end
        lib.jsmn_init(ctx)
    end
    local tokens = ffi_new(tok, m)
    lib.jsmn_parse(ctx, json, l, tokens, m)
    return (jsmn.obj(json, tokens, 0)), m
end
return jsmn