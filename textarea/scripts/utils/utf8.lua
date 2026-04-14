-- ─────────────────────────── utf8 ───────────────────────────────────

---@param s string
function utf8_len(s)
    if not s or s == "" then
        return 0
    end
    return utf8.len(s)
end

function utf8_charAt(s, ci)
    if ci < 1 or not s or s == "" then
        return ""
    end
    local b = utf8.offset(s, ci)
    if not b then
        return ""
    end
    local nb = utf8.offset(s, ci + 1)
    return nb and s:sub(b, nb - 1) or s:sub(b)
end

function utf8_sub(s, startChar, endChar)
    if not s or s == "" then
        return ""
    end
    endChar = endChar or utf8_len(s)
    local sb = utf8.offset(s, startChar)
    if not sb then
        return ""
    end
    local eb
    if endChar >= utf8_len(s) then
        eb = #s
    else
        eb = utf8.offset(s, endChar + 1)
        eb = eb and (eb - 1) or #s
    end
    return s:sub(sb, eb)
end

function isWordChar(ch)
    return #ch > 1 or ch:match("[%w_]") ~= nil
end

function isHorizontalSpace(ch)
    return ch == " "
end