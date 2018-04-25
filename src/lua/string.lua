local ffi = require('ffi')
local buffer = require('buffer')

ffi.cdef[[
    const char *
    memmem(const char *haystack, size_t haystack_len,
           const char *needle,   size_t needle_len);
    int memcmp(const char *mem1, const char *mem2, size_t num);
    int isspace(int c);

    typedef struct UCaseMap UCaseMap;
    typedef int UErrorCode;

    int32_t
    ucasemap_utf8ToLower(const UCaseMap *csm, char *dest, int32_t destCapacity,
                         const char *src, int32_t srcLength,
                         UErrorCode *pErrorCode);

    int32_t
    ucasemap_utf8ToUpper(const UCaseMap *csm, char *dest, int32_t destCapacity,
                         const char *src, int32_t srcLength,
                         UErrorCode *pErrorCode);

    UCaseMap *
    ucasemap_open(const char *locale, uint32_t options, UErrorCode *pErrorCode);

    void
    ucasemap_close(UCaseMap *csm);

    const char *
    u_errorName(UErrorCode code);

    int
    u_count(const char *s, int bsize, uint8_t flags);

    int
    u_compare(const char *s1, size_t len1, const char *s2, size_t len2);

    int
    u_icompare(const char *s1, size_t len1, const char *s2, size_t len2);
]]

local c_char_ptr = ffi.typeof('const char *')

local memcmp  = ffi.C.memcmp
local memmem  = ffi.C.memmem
local isspace = ffi.C.isspace

local err_string_arg = "bad argument #%d to '%s' (%s expected, got %s)"

local function string_split_empty(inp, maxsplit)
    local p = c_char_ptr(inp)
    local p_end = p + #inp
    local rv = {}
    while true do
        -- skip the leading whitespaces
        while p < p_end and isspace(p[0]) ~= 0 do
            p = p + 1
        end
        if p == p_end then
            break
        end
        if maxsplit <= 0 then
            table.insert(rv, ffi.string(p, p_end - p))
            break
        end
        local chunk = p
        -- skip all non-whitespace characters
        while p < p_end and isspace(p[0]) == 0 do
            p = p + 1
        end
        assert((p - chunk) > 0)
        table.insert(rv, ffi.string(chunk, p - chunk))
        maxsplit = maxsplit - 1
    end
    return rv
end

local function string_split_internal(inp, sep, maxsplit)
    local p = c_char_ptr(inp)
    local p_end = p + #inp
    local sep_len = #sep
    if sep_len == 0 then
        error(err_string_arg:format(2, 'string.split', 'non-empty string',
              "empty string"), 3)
    end
    local rv = {}
    while true do
        assert(p <= p_end)
        if maxsplit <= 0 or p == p_end then
            table.insert(rv, ffi.string(p, p_end - p))
            break
        end
        local chunk = p
        p = memmem(p, p_end - p, sep, sep_len)
        if p == nil then
            table.insert(rv, ffi.string(chunk, p_end - chunk))
            break
        end
        table.insert(rv, ffi.string(chunk, p - chunk))
        p = p + sep_len
        maxsplit = maxsplit - 1
    end
    return rv
end

local function string_split(inp, sep, max)
    if type(inp) ~= 'string' then
        error(err_string_arg:format(1, 'string.split', 'string', type(inp)), 2)
    end
    if sep ~= nil and type(sep) ~= 'string' then
        error(err_string_arg:format(2, 'string.split', 'string', type(sep)), 2)
    end
    if max ~= nil and (type(max) ~= 'number' or max < 0) then
        error(err_string_arg:format(3, 'string.split', 'positive integer',
                                    type(max)), 2)
    end
    max = max or 0xffffffff
    if not sep then
        return string_split_empty(inp, max)
    end
    return string_split_internal(inp, sep, max)
end

--- Left-justify string in a field of given width.
-- Append "width - len(inp)" chars to given string. Input is never trucated.
-- @function ljust
-- @string       inp    the string
-- @int          width  at least bytes to be returned
-- @string[opt]  char   char of length 1 to fill with (" " by default)
-- @returns             result string
local function string_ljust(inp, width, char)
    if type(inp) ~= 'string' then
        error(err_string_arg:format(1, 'string.ljust', 'string', type(inp)), 2)
    end
    if type(width) ~= 'number' or width < 0 then
        error(err_string_arg:format(2, 'string.ljust', 'positive integer',
                                    type(width)), 2)
    end
    if char ~= nil and (type(char) ~= 'string' or #char ~= 1) then
        error(err_string_arg:format(3, 'string.ljust', 'char',
                                    type(char)), 2)
    end
    char = char or " "
    local delta = width - #inp
    if delta < 0 then
        return inp
    end
    return inp .. char:rep(delta)
end

--- Right-justify string in a field of given width.
-- Prepend "width - len(inp)" chars to given string. Input is never trucated.
-- @function rjust
-- @string       inp    the string
-- @int          width  at least bytes to be returned
-- @string[opt]  char   char of length 1 to fill with (" " by default)
-- @returns             result string
local function string_rjust(inp, width, char)
    if type(inp) ~= 'string' then
        error(err_string_arg:format(1, 'string.rjust', 'string', type(inp)), 2)
    end
    if type(width) ~= 'number' or width < 0 then
        error(err_string_arg:format(2, 'string.rjust', 'positive integer',
                                    type(width)), 2)
    end
    if char ~= nil and (type(char) ~= 'string' or #char ~= 1) then
        error(err_string_arg:format(3, 'string.rjust', 'char',
                                    type(char)), 2)
    end
    char = char or " "
    local delta = width - #inp
    if delta < 0 then
        return inp
    end
    return char:rep(delta) .. inp
end

--- Center string in a field of given width.
-- Prepend and append "(width - len(inp))/2" chars to given string.
-- Input is never trucated.
-- @function center
-- @string       inp    the string
-- @int          width  at least bytes to be returned
-- @string[opt]  char   char of length 1 to fill with (" " by default)
-- @returns             result string
local function string_center(inp, width, char)
    if type(inp) ~= 'string' then
        error(err_string_arg:format(1, 'string.center', 'string', type(inp)), 2)
    end
    if type(width) ~= 'number' or width < 0 then
        error(err_string_arg:format(2, 'string.center', 'positive integer',
                                    type(width)), 2)
    end
    if char ~= nil and (type(char) ~= 'string' or #char ~= 1) then
        error(err_string_arg:format(3, 'string.center', 'char',
                                    type(char)), 2)
    end
    char = char or " "
    local delta = width - #inp
    if delta < 0 then
        return inp
    end
    local pad_left = math.floor(delta / 2)
    local pad_right = delta - pad_left
    return char:rep(pad_left) .. inp .. char:rep(pad_right)
end

-- For now the best way to check, that string starts with sequence
-- (with patterns disabled) is to cut line and check strings for equality

--- Check that string (or substring) starts with given string
-- Optionally restricting the matching with the given offsets
-- @function startswith
-- @string    inp     original string
-- @string    head    the substring to check against
-- @int[opt]  _start  start index of matching boundary
-- @int[opt]  _end    end index of matching boundary
-- @returns           boolean
local function string_startswith(inp, head, _start, _end)
    if type(inp) ~= 'string' then
        error(err_string_arg:format(1, 'string.startswith', 'string',
                                    type(inp)), 2)
    end
    if type(head) ~= 'string' then
        error(err_string_arg:format(2, 'string.startswith', 'string',
                                    type(head)), 2)
    end
    if _start ~= nil and type(_start) ~= 'number' then
        error(err_string_arg:format(3, 'string.startswith', 'integer',
                                    type(_start)), 2)
    end
    if _end ~= nil and type(_end) ~= 'number' then
        error(err_string_arg:format(4, 'string.startswith', 'integer',
                                    type(_end)), 2)
    end
    -- prepare input arguments (move negative values [offset from the end] to
    -- positive ones and/or assign default values)
    local head_len, inp_len = #head, #inp
    if _start == nil then
        _start = 1
    elseif _start < 0 then
        _start = inp_len + _start + 1
        if _start < 0 then _start = 0 end
    end
    if _end == nil or _end > inp_len then
        _end = inp_len
    elseif _end < 0 then
        _end = inp_len + _end + 1
        if _end < 0 then _end = 0 end
    end
    -- check for degenerate case (interval lesser than input)
    if head_len == 0 then
        return true
    elseif _end - _start + 1 < head_len or _start > _end then
        return false
    end
    _start = _start - 1
    _end = _start + head_len - 1
    return memcmp(c_char_ptr(inp) + _start, c_char_ptr(head), head_len) == 0
end

--- Check that string (or substring) ends with given string
-- Optionally restricting the matching with the given offsets
-- @function endswith
-- @string    inp     original string
-- @string    tail    the substring to check against
-- @int[opt]  _start  start index of matching boundary
-- @int[opt]  _end    end index of matching boundary
-- @returns           boolean
local function string_endswith(inp, tail, _start, _end)
    local tail_len, inp_len = #tail, #inp
    if type(inp) ~= 'string' then
        error(err_string_arg:format(1, 'string.endswith', 'string',
                                    type(inp)), 2)
    end
    if type(tail) ~= 'string' then
        error(err_string_arg:format(2, 'string.endswith', 'string',
                                    type(inp)), 2)
    end
    if _start ~= nil and type(_start) ~= 'number' then
        error(err_string_arg:format(3, 'string.endswith', 'integer',
                                    type(inp)), 2)
    end
    if _end ~= nil and type(_end) ~= 'number' then
        error(err_string_arg:format(4, 'string.endswith', 'integer',
                                    type(inp)), 2)
    end
    -- prepare input arguments (move negative values [offset from the end] to
    -- positive ones and/or assign default values)
    if _start == nil then
        _start = 1
    elseif _start < 0 then
        _start = inp_len + _start + 1
        if _start < 0 then _start = 0 end
    end
    if _end == nil or _end > inp_len then
        _end = inp_len
    elseif _end < 0 then
        _end = inp_len + _end + 1
        if _end < 0 then _end = 0 end
    end
    -- check for degenerate case (interval lesser than input)
    if tail_len == 0 then
        return true
    elseif _end - _start + 1 < tail_len or _start > _end  then
        return false
    end
    _start = _end - tail_len
    return memcmp(c_char_ptr(inp) + _start, c_char_ptr(tail), tail_len) == 0
end

local function string_hex(inp)
    if type(inp) ~= 'string' then
        error(err_string_arg:format(1, 'string.hex', 'string', type(inp)), 2)
    end
    local len = inp:len() * 2
    local res = ffi.new('char[?]', len + 1)

    local uinp = ffi.cast('const unsigned char *', inp)
    for i = 0, inp:len() - 1 do
        ffi.C.snprintf(res + i * 2, 3, "%02x", ffi.cast('unsigned', uinp[i]))
    end
    return ffi.string(res, len)
end

local function string_strip(inp)
    if type(inp) ~= 'string' then
        error(err_string_arg:format(1, "string.strip", 'string', type(inp)), 2)
    end
    return (string.gsub(inp, "^%s*(.-)%s*$", "%1"))
end

local function string_lstrip(inp)
    if type(inp) ~= 'string' then
        error(err_string_arg:format(1, "string.lstrip", 'string', type(inp)), 2)
    end
    return (string.gsub(inp, "^%s*(.-)", "%1"))
end

local function string_rstrip(inp)
    if type(inp) ~= 'string' then
        error(err_string_arg:format(1, "string.rstrip", 'string', type(inp)), 2)
    end
    return (string.gsub(inp, "(.-)%s*$", "%1"))
end

--
-- ICU bindings.
--
--
-- Ucasemap cache allows to do not create a new UCaseMap on each
-- u_upper/u_lower call. References are weak to do not keep all
-- ever created maps, so the cache is cleared periodically.
--
local ucasemap_cache = setmetatable({}, {__mode = 'v'})
local errcode = ffi.new('int[1]')
errcode[0] = 0
--
-- ICU UCaseMethod requires 0 error code as input, so after any
-- error the errcode must be nullified.
--
local function icu_clear_error()
    errcode[0] = 0
end
--
-- String representation of the latest ICU error.
--
local function icu_error()
    return ffi.string(ffi.C.u_errorName(errcode[0]))
end
--
-- Find cached UCaseMap for @a locale, or create a new one and
-- cache it.
-- @param locale String locale or box.NULL for default.
-- @retval nil Can neither get or create a UCaseMap.
-- @retval not nil Needed UCaseMap.
--
local function ucasemap_retrieve(locale)
    local ret = ucasemap_cache[locale]
    if not ret then
        ret = ffi.C.ucasemap_open(c_char_ptr(locale), 0, errcode)
        if ret ~= nil then
            ffi.gc(ret, ffi.C.ucasemap_close)
            ucasemap_cache[locale] = ret
        end
    end
    return ret
end
--
-- Check ICU options for string.u_upper/u_lower.
-- @param opts Options. Can contain only one option - locale.
-- @param usage_err What to throw if opts types are violated.
-- @retval String locale if found.
-- @retval box.NULL if locale is not found.
--
local function icu_check_case_opts(opts, usage_err)
    if opts then
        if type(opts) ~= 'table' then
            error(usage_err)
        end
        if opts.locale then
            if type(opts.locale) ~= 'string' then
                error(usage_err)
            end
            return opts.locale
        end
    end
    return box.NULL
end
--
-- Create upper/lower case version of @an inp string.
-- @param inp Input string.
-- @param opts Options. Can contain only one option - locale. In
--        different locales different capital letters can exist
--        for the same symbol. For example, in turkish locale
--        upper('i') == 'İ', in english locale it is 'I'. See ICU
--        documentation for locales.
-- @param func Upper or lower FFI function.
-- @param usage What to print on usage error.
-- @retval nil, error Error.
-- @retval not nil Uppercase version of @an inp.
--
local function string_u_to_case_impl(inp, opts, func, usage)
    if type(inp) ~= 'string' then
        error(usage)
    end
    icu_clear_error()
    local map = ucasemap_retrieve(icu_check_case_opts(opts, usage))
    if not map then
        return nil, icu_error()
    end
    local src_len = #inp
    inp = c_char_ptr(inp)
    local buf = buffer.IBUF_SHARED
    local buf_raw, ret
    -- +1 for NULL termination. Else error appears in errcode.
    local dst_len = src_len + 1
::do_convert::
    buf:reset()
    buf_raw = buf:alloc(dst_len)
    ret = func(map, buf_raw, dst_len, inp, src_len, errcode)
    if ret <= dst_len then
        if ret == 0 and errcode[0] ~= 0 then
            return nil, icu_error()
        end
        return ffi.string(buf_raw, ret)
    else
        dst_len = ret + 1
        goto do_convert
    end
end

local function string_u_upper(inp, opts)
    local usage = 'Usage: string.u_upper(str, {[locale = <string>}])'
    return string_u_to_case_impl(inp, opts, ffi.C.ucasemap_utf8ToUpper, usage)
end

local function string_u_lower(inp, opts)
    local usage = 'Usage: string.u_lower(str, {[locale = <string>}])'
    return string_u_to_case_impl(inp, opts, ffi.C.ucasemap_utf8ToLower, usage)
end

local U_COUNT_CLASS_ALL = 0
local U_COUNT_CLASS_UPPER_LETTER = 1
local U_COUNT_CLASS_LOWER_LETTER = 2
local U_COUNT_CLASS_LETTER = 4
local U_COUNT_CLASS_DIGIT = 8

--
-- Calculate count of symbols matching the needed classes.
-- @param inp Input UTF8 string.
-- @param opts Options with needed classes. It supports 'all',
--        'upper', 'lower', 'letter', 'digit'. Opts is a table,
--        where needed class key is set to true. By default all
--        classes are needed, and count works like strlen (not
--        bsize, like Lua operator '#').
-- @retval not nil Summary count of needed symbols.
-- @retval nil, position Invalid UTF8 on returned position.
--
local function string_u_count(inp, opts)
    local usage = 'Usage: string.u_count(str)'
    if type(inp) ~= 'string' then
        error(usage)
    end
    local flags = 0
    if opts then
        if type(opts) ~= 'table' then
            error(usage)
        end
        if not opts.all then
            if not opts.letter then
                if opts.upper then
                    flags = bit.bor(flags, U_COUNT_CLASS_UPPER_LETTER)
                end
                if opts.lower then
                    flags = bit.bor(flags, U_COUNT_CLASS_LOWER_LETTER)
                end
            else
                flags = bit.bor(flags, U_COUNT_CLASS_LETTER)
            end
            if opts.digit then
                flags = bit.bor(flags, U_COUNT_CLASS_DIGIT)
            end
        end
    end
    local len = #inp
    inp = c_char_ptr(inp)
    local ret = ffi.C.u_count(inp, len, flags)
    if ret >= 0 then
        return ret
    else
        return nil, -ret
    end
end

--
-- Compare two UTF8 strings.
-- @param inp1 First string.
-- @param inp2 Second string.
-- @param func Comparator - case sensitive or insensitive.
-- @param usage Error on incorrect usage.
-- @retval  <0 inp1 < inp2
-- @retval  >0 inp1 > inp2
-- @retval ==0 inp1 == inp2
--
local function string_u_compare_impl(inp1, inp2, func, usage)
    if type(inp1) ~= 'string' or type(inp2) ~= 'string' then
        error(usage)
    end
    return func(c_char_ptr(inp1), #inp1, c_char_ptr(inp2), #inp2)
end

local function string_u_compare(inp1, inp2)
    return string_u_compare_impl(inp1, inp2, ffi.C.u_compare,
                                 'Usage: string.u_compare(<string>, <string>)')
end

local function string_u_icompare(inp1, inp2)
    return string_u_compare_impl(inp1, inp2, ffi.C.u_icompare,
                                 'Usage: string.u_icompare(<string>, <string>)')
end

-- It'll automatically set string methods, too.
local string = require('string')
string.split      = string_split
string.ljust      = string_ljust
string.rjust      = string_rjust
string.center     = string_center
string.startswith = string_startswith
string.endswith   = string_endswith
string.hex        = string_hex
string.strip      = string_strip
string.lstrip      = string_lstrip
string.rstrip      = string_rstrip
string.u_upper    = string_u_upper
string.u_lower    = string_u_lower
string.u_count    = string_u_count
string.u_compare  = string_u_compare
string.u_icompare = string_u_icompare
