local T = require("helper")
local it = T.it

package.preload["logger"] = package.preload["logger"] or function()
    local function noop() end
    return { info = noop, warn = noop, dbg = noop, err = noop }
end

local DictionaryStore = T.load("dictionary_store")
local DictionaryIndex = T.load("dictionary_index")
local TOOL = T.plugin_dir .. "/../tools/drop_foreign_words.py"

local function write(path, text)
    local file = assert(io.open(path, "w"))
    file:write(text)
    file:close()
end

local function read(path)
    local file = io.open(path)
    if not file then return nil end
    local text = file:read("*a")
    file:close()
    return text
end

local function newDir()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute('mkdir -p "' .. dir .. '"')
    return dir
end

-- A package of { word, frequency } rows, as the tool reads one: its rows
-- need not be in order, as it writes them out again.
local function newPackage(language, words)
    local dir = newDir()
    local lines = {}
    for _, entry in ipairs(words) do
        lines[#lines + 1] = entry[1]:lower() .. "\t" .. entry[1] .. "\t"
            .. entry[2] .. "\t" .. language .. "\n"
    end
    write(dir .. "/words.buckets.tsv", table.concat(lines))
    write(dir .. "/manifest.tsv", "# field\tvalue\nid\t" .. language
        .. "\ndata_language\t" .. language .. "\nversion\t2.1.0\nrows\t"
        .. #lines .. "\n")
    write(dir .. "/ATTRIBUTION.txt", "kept as it is\n")
    return dir
end

-- Whether tool (TOOL by default) ran and succeeded with these options.
local function run(options, tool)
    local ok = os.execute("python3 " .. (tool or TOOL) .. " " .. options
        .. " >/dev/null 2>&1")
    return ok == 0 or ok == true
end

local function newStore(dir)
    local files = {
        bucket_data = dir .. "/words.buckets.tsv",
        bucket_index = dir .. "/words.buckets.idx",
        popular_data = dir .. "/words.popular.tsv",
        popular_index = dir .. "/words.popular.idx",
    }
    local registry = {
        get = function(_, id)
            return { id = id, data_language = id, files = files }
        end,
    }
    return DictionaryStore:new(dir, registry, DictionaryIndex,
        { now = function() return 0 end, ms = function(n) return n end })
end

local function sha256(path)
    local pipe = assert(io.popen('sha256sum "' .. path .. '"'))
    local line = pipe:read("*l") or ""
    pipe:close()
    return line:match("^(%x+)")
end

local function remove(...)
    for _, dir in ipairs({ ... }) do
        os.execute('rm -rf "' .. dir .. '"')
    end
end

local ENGLISH = {
    { "the", 7730 }, { "love", 5900 }, { "site", 5000 }, { "no", 6000 },
    { "Michael", 5000 }, { "team", 5300 }, { "casa", 3000 },
}
local PORTUGUESE = {
    { "the", 6000 }, { "love", 4900 }, { "site", 4800 }, { "no", 6500 },
    { "Michael", 4500 }, { "team", 4800 }, { "casa", 6000 },
}

it("leaves out the English words a language's list quotes", function()
    local english = newPackage("en", ENGLISH)
    local package = newPackage("pt", PORTUGUESE)
    local known = package .. "/known.txt"
    write(known, "casa\nno\nsite\n")
    T.truthy(run("--english " .. english .. " --known " .. known
        .. " --min-known 1 --version 2.2.0 --report " .. package
        .. "/report.tsv " .. package), "drop_foreign_words.py ran")
    local store = newStore(package)
    -- English uses "the" 50 times as often and "love" 10 times.
    T.eq(store:findWord("the", "the", "pt"), nil)
    T.eq(store:findWord("love", "love", "pt"), nil)
    T.eq(store:findWord("site", "site", "pt"), "site", "Wiktionary knows it")
    T.eq(store:findWord("no", "no", "pt"), "no", "a word in both")
    T.eq(store:findWord("michael", "michael", "pt"), "Michael",
        "English capitalizes it: a name")
    T.eq(store:findWord("team", "team", "pt"), "team",
        "used about as much as in English")
    T.eq(store:findWord("casa", "casa", "pt"), "casa", "rarer in English")
    for _, entry in ipairs(store:loadPopularWords("t", "pt")) do
        T.truthy(entry.word ~= "the", "not among the popular words")
    end
    T.eq(read(package .. "/report.tsv"),
        "# spelling\tfrequency\tEnglish frequency\n"
        .. "the\t6000\t7730\nlove\t4900\t5900\n")
    local manifest = read(package .. "/manifest.tsv")
    T.truthy(manifest:find("\nversion\t2.2.0\n"), manifest)
    T.truthy(manifest:find("\nrows\t5\n"), manifest)
    T.truthy(manifest:find("\nsha256_data\t"
        .. sha256(package .. "/words.buckets.tsv") .. "\n"), manifest)
    T.truthy(manifest:find("\nsha256_popular_index\t"
        .. sha256(package .. "/words.popular.idx") .. "\n"), manifest)
    T.eq(read(package .. "/ATTRIBUTION.txt"), "kept as it is\n")
    remove(english, package)
end)

it("leaves a package as it is when Wiktionary's list is short", function()
    local english = newPackage("en", ENGLISH)
    local package = newPackage("pt", PORTUGUESE)
    local before = read(package .. "/words.buckets.tsv")
    local known = package .. "/known.txt"
    write(known, "casa\nno\nsite\n")
    T.truthy(not run("--english " .. english .. " --known " .. known
        .. " --version 2.2.0 " .. package), "refused a list of 3 words")
    T.truthy(not run("--english " .. english .. " --known " .. known
        .. " --min-known 1 " .. package), "refused without a version")
    T.eq(read(package .. "/words.buckets.tsv"), before)
    T.truthy(not run("--english " .. english .. " --known " .. known
        .. " --min-known 1 --version 2.2.0 " .. english),
        "refused the English package")
    remove(english, package)
end)

it("builds without English words only from a full Wiktionary list",
        function()
    local english = newPackage("en", ENGLISH)
    local dir = newDir()
    write(dir .. "/known.txt", "casa\nno\nsite\n")
    -- "the" once in 941 words: Zipf 6.03, 1.7 below English's 7.73.
    write(dir .. "/words.txt", "1\tthe\t1\n2\tcasa\t900\n3\tsite\t40\n")
    local function build(options)
        return run("--id pt-br --source-language pt"
            .. " --keyboard-layout pt_keyboard --min-count 1 --english "
            .. english .. " --known " .. dir .. "/known.txt --out " .. dir
            .. "/out " .. options .. " " .. dir .. "/words.txt",
            T.plugin_dir .. "/../tools/build_dictionary.py")
    end
    T.truthy(not build(""), "refused a list of 3 words")
    T.eq(read(dir .. "/out/manifest.tsv"), nil, "and wrote nothing")
    T.truthy(build("--min-known 1"), "built with the floor lowered")
    local store = newStore(dir .. "/out")
    T.eq(store:findWord("casa", "casa", "pt"), "casa")
    T.eq(store:findWord("the", "the", "pt"), nil)
    remove(english, dir)
end)
