#!/usr/bin/env tarantool

local tap = require('tap')
local test = tap.test("string extensions")

test:plan(6)

test:test("split", function(test)
    test:plan(10)

    -- testing basic split (works over gsplit)
    test:ok(not pcall(string.split, "", ""), "empty separator")
    test:ok(not pcall(string.split, "a", ""), "empty separator")
    test:is_deeply((""):split("z"), {""},  "empty split")
    test:is_deeply(("a"):split("a"), {"", ""}, "split self")
    test:is_deeply(
        (" 1 2  3  "):split(),
        {"1", "2", "3"},
        "complex split on empty separator"
    )
    test:is_deeply(
        (" 1 2  3  "):split(" "),
        {"", "1", "2", "", "3", "", ""},
        "complex split on space separator"
    )
    test:is_deeply(
        (" 1 2  \n\n\n\r\t\n3  "):split(),
        {"1", "2", "3"},
        "complex split on empty separator"
    )
    test:is_deeply(
        ("a*bb*c*ddd"):split("*"),
        {"a", "bb", "c", "ddd"},
        "another * separator"
    )
    test:is_deeply(
        ("dog:fred:bonzo:alice"):split(":", 2),
        {"dog", "fred", "bonzo:alice"},
        "testing max separator"
    )
    test:is_deeply(
        ("///"):split("/"),
        {"", "", "", ""},
        "testing splitting on one char"
    )
end)

-- gh-2214 - string.ljust()/string.rjust() Lua API
test:test("ljust/rjust/center", function(test)
    test:plan(18)

    test:is(("help"):ljust(0),  "help", "ljust, length 0, do nothing")
    test:is(("help"):rjust(0),  "help", "rjust, length 0, do nothing")
    test:is(("help"):center(0), "help", "center, length 0, do nothing")

    test:is(("help"):ljust(3),  "help", "ljust, length 3, do nothing")
    test:is(("help"):rjust(3),  "help", "rjust, length 3, do nothing")
    test:is(("help"):center(3), "help", "center, length 3, do nothing")

    test:is(("help"):ljust(5),  "help ", "ljust, length 5, one extra charachter")
    test:is(("help"):rjust(5),  " help", "rjust, length 5, one extra charachter")
    test:is(("help"):center(5), "help ", "center, length 5, one extra charachter")

    test:is(("help"):ljust(6),  "help  ", "ljust, length 6, two extra charachters")
    test:is(("help"):rjust(6),  "  help", "rjust, length 6, two extra charachters")
    test:is(("help"):center(6), " help ", "center, length 6, two extra charachters")

    test:is(("help"):ljust(6, '.'),  "help..", "ljust, length 6, two extra charachters, custom fill char")
    test:is(("help"):rjust(6, '.'),  "..help", "rjust, length 6, two extra charachters, custom fill char")
    test:is(("help"):center(6, '.'), ".help.", "center, length 6, two extra charachters, custom fill char")
    local errmsg = "%(char expected, got string%)"
    local _, err = pcall(function() ("help"):ljust(6, "XX") end)
    test:ok(err and err:match(errmsg), "wrong params")
    _, err = pcall(function() ("help"):rjust(6, "XX") end)
    test:ok(err and err:match(errmsg), "wrong params")
    _, err = pcall(function() ("help"):center(6, "XX") end)
    test:ok(err and err:match(errmsg), "wrong params")
end)

-- gh-2215 - string.startswith()/string.endswith() Lua API
test:test("startswith/endswith", function(test)
    test:plan(21)

    test:ok((""):startswith(""),      "empty+empty startswith")
    test:ok((""):endswith(""),        "empty+empty endswith")
    test:ok(not (""):startswith("a"), "empty+non-empty startswith")
    test:ok(not (""):endswith("a"),   "empty+non-empty endswith")
    test:ok(("a"):startswith(""),     "non-empty+empty startswith")
    test:ok(("a"):endswith(""),       "non-empty+empty endswith")

    test:ok(("12345"):startswith("123")            , "simple startswith")
    test:ok(("12345"):startswith("123", 1, 5)      , "startswith with good begin/end")
    test:ok(("12345"):startswith("123", 1, 3)      , "startswith with good begin/end")
    test:ok(("12345"):startswith("123", -5, 3)     , "startswith with good negative begin/end")
    test:ok(("12345"):startswith("123", -5, -3)    , "startswith with good negative begin/end")
    test:ok(not ("12345"):startswith("123", 2, 5)  , "bad startswith with good begin/end")
    test:ok(not ("12345"):startswith("123", 1, 2)  , "bad startswith with good begin/end")

    test:ok(("12345"):endswith("345")              , "simple endswith")
    test:ok(("12345"):endswith("345", 1, 5)        , "endswith with good begin/end")
    test:ok(("12345"):endswith("345", 3, 5)        , "endswith with good begin/end")
    test:ok(("12345"):endswith("345", -3, 5)       , "endswith with good begin/end")
    test:ok(("12345"):endswith("345", -3, -1)      , "endswith with good begin/end")
    test:ok(not ("12345"):endswith("345", 1, 4)    , "bad endswith with good begin/end")
    test:ok(not ("12345"):endswith("345", 4, 5)    , "bad endswith with good begin/end")

    local _, err = pcall(function() ("help"):startswith({'n', 1}) end)
    test:ok(err and err:match("%(string expected, got table%)"), "wrong params")
end)

test:test("hex", function(test)
    test:plan(2)
    test:is(string.hex("hello"), "68656c6c6f", "hex non-empty string")
    test:is(string.hex(""), "", "hex empty string")
end)

test:test("unicode", function(test)
    test:plan(13)
    local str = 'хеЛлоу вОрЛд ё Ё я Я э Э ъ Ъ hElLo WorLd 1234 i I İ 勺#☢༺'
    local upper_res = 'ХЕЛЛОУ ВОРЛД Ё Ё Я Я Э Э Ъ Ъ HELLO WORLD 1234 I I İ 勺#☢༺'
    local upper_turkish = 'ХЕЛЛОУ ВОРЛД Ё Ё Я Я Э Э Ъ Ъ HELLO WORLD 1234 İ I İ 勺#☢༺'
    local lower_res = 'хеллоу ворлд ё ё я я э э ъ ъ hello world 1234 i i i̇ 勺#☢༺'
    local lower_turkish = 'хеллоу ворлд ё ё я я э э ъ ъ hello world 1234 i ı i 勺#☢༺'
    local s = string.u_upper(str)
    test:is(s, upper_res, 'default locale upper')
    s = string.u_lower(str)
    test:is(s, lower_res, 'default locale lower')
    s = string.u_upper(str, {locale = 'en_US'})
    test:is(s, upper_res, 'en_US locale upper')
    s = string.u_lower(str, {locale = 'en_US'})
    test:is(s, lower_res, 'en_US locale lower')
    s = string.u_upper(str, {locale = 'ru_RU'})
    test:is(s, upper_res, 'ru_RU locale upper')
    s = string.u_lower(str, {locale = 'ru_RU'})
    test:is(s, lower_res, 'ru_RU locale lower')
    s = string.u_upper(str, {locale = 'tr_TR'})
    test:is(s, upper_turkish, 'tr_TR locale upper')
    s = string.u_lower(str, {locale = 'tr_TR'})
    test:is(s, lower_turkish, 'tr_TR locale lower')
    local err
    s, err = string.u_upper(str, {locale = 'not_existing locale tratatatata'})
    test:is(s, upper_res, 'incorrect locale turns into default upper')
    test:isnil(err, 'upper error is nil')
    s, err = string.u_lower(str, {locale = 'not_existing locale tratatatata'})
    test:is(s, lower_res, 'incorrect locale turns into default lower')
    test:isnil(err, 'lower error is nil')
    test:is(string.u_upper('ß', {locale = 'de_DE'}), 'SS',
            'ß produces two symbols')
end)

test:test("strip", function(test)
    test:plan(6)
    local str = "  hello hello "
    test:is(string.len(string.strip(str)), 11, "strip")
    test:is(string.len(string.lstrip(str)), 12, "lstrip")
    test:is(string.len(string.rstrip(str)), 13, "rstrip")
    local _, err = pcall(string.strip, 12)
    test:ok(err and err:match("%(string expected, got number%)"))
    _, err = pcall(string.lstrip, 12)
    test:ok(err and err:match("%(string expected, got number%)"))
    _, err = pcall(string.rstrip, 12)
    test:ok(err and err:match("%(string expected, got number%)"))
end )

os.exit(test:check() == true and 0 or -1)
