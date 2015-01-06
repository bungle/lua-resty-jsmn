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
local lib = ffi_load("/Users/bungle/Sources/lua-resty-jsmn/lib/resty/libjsmn.so")
local ctx = ffi_typeof("jsmn_parser")
local tok = ffi_typeof("jsmntok_t[?]")
local ok, newtab = pcall(require, "table.new")
if not ok then newtab = function (narr, nrec) return {} end  end
local jsmn = newtab(0, 4)
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
    if not l then l = #json end
    if not m then
        m = tonumber(lib.jsmn_parse(ctx, json, l, nil, 0))
        lib.jsmn_init(ctx)
        if m < 1 then return nil, m end
    end
    local tokens = ffi_new(tok, m)
    lib.jsmn_parse(ctx, json, l, tokens, m)
    if not tokens then return nil, m end
    local n, l, k = newtab(m, 0), m - 1, nil
    for i=0, l do
        local token = tokens[i]
        local t, z, s, e, p, v = token.type, token.size, token.start + 1, token["end"], token.parent, nil
        if t == C.JSMN_PRIMITIVE then
            n[i] = n[p]
            local  c = sub(json, s, s)
            if     c == "f" then v = false
            elseif c == "t" then v = true
            elseif c == "n" then v = null
            else                 v = tonumber(sub(json, s, e)) end
        elseif t == C.JSMN_OBJECT then
            v = setmetatable(newtab(0, z), obj)
            n[i] = v
        elseif t == C.JSMN_ARRAY then
            v = setmetatable(newtab(z, 0), arr)
            n[i] = v
        elseif t == C.JSMN_STRING then
            n[i] = n[p]
            if z == 1 then
                k = sub(json, s, e)
            else
                v = sub(json, s, e)
            end
        end
        if k ~= nil and v ~= nil then
            p = n[p]
            if getmetatable(p) == arr then
                p[#p + 1] = v
            else
                p[k] = v
            end
        end
    end
    return n[0], m
end
return jsmn