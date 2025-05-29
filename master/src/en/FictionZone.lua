-- {"id":1413038472,"ver":"1.0.0","libVer":"1.0.0","author":"Zaeems","dep":["url>=1.0.0","CommonCSS>=1.0.0","unhtml>=1.0.0"]}
local baseURL = "https://www.fictionzone.net"
local cdnBaseURL = "https://cdn.fictionzone.net/insecure/rs:force:{W}:{H}:0/q:90/plain/local:///"
local apiURL = baseURL .. "/api/__api_party/api-v1"

local qs = Require("url").querystring
local HTMLToString = Require("unhtml").HTMLToString
local css = Require("CommonCSS").table

local novelIdCache = {}

local FILTER_SORT_KEY = 100
local FILTER_STATUS_KEY = 200

local SORT_OPTIONS_EXT = {"Popularity (Weekly)", "Relevance", "Newest", "Last Updated", "Popularity (All Time)",
                          "Popularity (Monthly)", "Popularity (Daily)", "Rating", "Bookmarks", "Chapter Count"}
local SORT_OPTIONS_INT = {
    [1] = "views-week",
    [2] = nil,
    [3] = "newest",
    [4] = "updated_at",
    [5] = "views-all",
    [6] = "views-month",
    [7] = "views-day",
    [8] = "rating",
    [9] = "bookmark_count",
    [10] = "chapter_count"
}

local STATUS_OPTIONS_EXT = {"All", "Ongoing", "Completed"}
local STATUS_OPTIONS_INT = {
    [1] = 0,
    [2] = 1,
    [3] = 2
}

local function makeApiRequest(path, queryParams, page)
    local payloadQuery = queryParams or {}
    if page and page > 0 then
        payloadQuery.page = page
    end

    local payload = {
        path = path,
        query = payloadQuery,
        headers = {
            ["content-type"] = "application/json"
        },
        method = "get"
    }
    
    -- Log("API Request Payload: " .. jsonEncode(payload))
    local resp = POST(apiURL, Headers(), RequestBody(jsonEncode(payload)))
    if resp:isSuccessful() then
        local jsonData = jsonDecode(resp:body())
        -- Log("API Response: " .. resp:body():sub(1,500)) -- Log first 500 chars of response
        if jsonData and jsonData._success then
            return jsonData
        else
            Log("API request not successful or failed to parse. Path: " .. path .. ". Message: " ..
                    (jsonData and jsonData._messages or "Unknown error"))
            return nil
        end
    else
        Log("API request failed. Path: " .. path .. ". Status: " .. resp:code())
        return nil
    end
end

local function constructImageURL(imagePath, width, height)
    if not imagePath or imagePath == "" then
        return nil
    end
    local url = cdnBaseURL:gsub("{W}", tostring(width)):gsub("{H}", tostring(height))
    return CDN(url .. imagePath .. "@webp")
end

local function parseNovelFromListAPI(apiNovelObj, defaultWidth, defaultHeight)
    if not apiNovelObj then
        return nil
    end

    local genres = {}
    if apiNovelObj.genres and type(apiNovelObj.genres) == "table" then
        for _, g in ipairs(apiNovelObj.genres) do
            if g and g.name then
                table.insert(genres, g.name)
            end
        end
    end

    if apiNovelObj.slug and apiNovelObj.id then
        novelIdCache[tostring(apiNovelObj.slug)] = apiNovelObj.id
    end

    return Novel {
        title = apiNovelObj.title,
        link = apiNovelObj.slug,
        imageURL = constructImageURL(apiNovelObj.image, defaultWidth or 150, defaultHeight or 220),
        id_for_extension = apiNovelObj.id,
        genres = genres,
        status = (apiNovelObj.status == 1 and NovelStatus.PUBLISHING or
            (apiNovelObj.status == 2 and NovelStatus.COMPLETED or NovelStatus.UNKNOWN))
    }
end

local function getList(name, apiPathKeyInHomeResponse)
    return Listing(name, false, function(data)
        -- The /novel/public/home endpoint doesn't take page query for its sub-arrays directly.
        -- It returns all items for these sections in one go.
        -- Pagination for these specific homepage carousels is usually client-side or limited display.
        -- For a full "browse" of these, a different API endpoint or search with sort would be needed.
        -- Here, we assume it returns enough for a typical listing's first page.
        local apiResponse = makeApiRequest("/novel/public/home", nil, 1) -- Fetch homepage data
        if not apiResponse or not apiResponse._data or not apiResponse._data[apiPathKeyInHomeResponse] then
            return {}
        end

        local novels = {}
        for _, novelData in ipairs(apiResponse._data[apiPathKeyInHomeResponse]) do
            local novel = parseNovelFromListAPI(novelData, 150, 220)
            if novel then
                table.insert(novels, novel)
            end
        end
        return novels
    end)
end

local function getLatestUpdatesList()
    return Listing("Latest Updates", false, function(data)
        -- This API path might not support pagination in its query. It might return a fixed set.
        local apiResponse = makeApiRequest("/novel/public/latestchapter", {}, data[PAGE])
        if not apiResponse or not apiResponse._data then
            return {}
        end

        table.sort(apiResponse._data, function(a, b)
            return (a.chapter_created_at or "") > (b.chapter_created_at or "")
        end)

        local novels = {}
        for _, item in ipairs(apiResponse._data) do
            if item.slug and item.id then
                novelIdCache[tostring(item.slug)] = item.id
            end
            table.insert(novels, Novel {
                title = item.title,
                link = item.slug,
                imageURL = constructImageURL(item.image, 115, 160),
                id_for_extension = item.id,
                latestChapter = item.latest_chapter and item.latest_chapter.title or nil
            })
        end
        return novels
    end)
end

local function shrinkURL(url, type)
    url = url:gsub("https://fictionzone%.net/", "")
    if type == 1 then -- Novel URL: /novel/{slug}
        url = url:gsub("^novel/", "")
    elseif type == 2 then -- Chapter URL: /novel/{novel_slug}/{chapter_slug}
        url = url:gsub("^novel/", "") -- Stores {novel_slug}/{chapter_slug}
    end
    return url
end

local function expandURL(shrunk_url, type)
    if type == 1 then -- Novel
        return baseURL .. "/novel/" .. shrunk_url
    elseif type == 2 then -- Chapter
        return baseURL .. "/novel/" .. shrunk_url -- shrunk_url is already {novel_slug}/{chapter_slug}
    end
    return baseURL .. "/" .. shrunk_url
end

local function getNovelIdFromSlug(novel_slug)
    if novelIdCache[tostring(novel_slug)] then
        return novelIdCache[tostring(novel_slug)]
    end
    Log("Novel ID for slug '" .. novel_slug .. "' not in cache. Fetching from API.")
    local searchResponse = makeApiRequest("/novel", {
        query = novel_slug,
        limit = 1
    })
    if searchResponse and searchResponse._data and #searchResponse._data > 0 then
        for _, foundNovel in ipairs(searchResponse._data) do
            if foundNovel.slug == novel_slug then
                novelIdCache[tostring(novel_slug)] = foundNovel.id
                return foundNovel.id
            end
        end
    end
    Log("Failed to retrieve novel_id for slug: " .. novel_slug)
    return nil
end

return {
    id = 1413038472,
    name = "FictionZone",
    baseURL = baseURL,
    imageURL = "https://fictionzone.net/favicon-16x16.png",
    version = "1.0.1",
    hasCloudFlare = true,
    chapterType = ChapterType.HTML,

    listings = {getList("New Releases", "new"), getList("Most Popular (All Time)", "all_views"),
                getList("Most Popular (Daily)", "day_views"), getList("Most Popular (Weekly)", "week_views"),
                getList("Most Popular (Monthly)", "month_views"), getList("Recently Completed", "complete"),
                getLatestUpdatesList(), getList("Random Picks", "random")},

    shrinkURL = shrinkURL,
    expandURL = expandURL,

    search = function(data)
        local queryParams = {
            query = data[QUERY]
        }
        local sort = SORT_OPTIONS_INT[data[FILTER_SORT_KEY] or 1]
        local status = STATUS_OPTIONS_INT[data[FILTER_STATUS_KEY] or 1]

        if sort then
            queryParams.sort = sort
        end
        if status and status ~= 0 then
            queryParams.status = status
        end

        local apiResponse = makeApiRequest("/novel", queryParams, data[PAGE])
        if not apiResponse or not apiResponse._data then
            return {}, false
        end

        local novels = {}
        for _, novelData in ipairs(apiResponse._data) do
            local novel = parseNovelFromListAPI(novelData, 150, 220)
            if novel then
                table.insert(novels, novel)
            end
        end

        local hasNextPage = false
        if apiResponse._extra and apiResponse._extra._pagination then
            hasNextPage = (apiResponse._extra._pagination._current or 1) < (apiResponse._extra._pagination._last or 1)
        end
        return novels, hasNextPage
    end,
    isSearchIncrementing = true,
    searchFilters = {DropdownFilter(FILTER_SORT_KEY, "Sort by", SORT_OPTIONS_EXT),
                     DropdownFilter(FILTER_STATUS_KEY, "Status", STATUS_OPTIONS_EXT)},

    parseNovel = function(novel_slug_or_data, loadChapters)
        local novel_slug
        local novel_id
        local api_novel_data_from_list

        if type(novel_slug_or_data) == "string" then
            novel_slug = novel_slug_or_data
            novel_id = getNovelIdFromSlug(novel_slug)
        else
            api_novel_data_from_list = novel_slug_or_data
            novel_slug = api_novel_data_from_list.link
            novel_id = api_novel_data_from_list.id_for_extension
            if novel_id then
                novelIdCache[tostring(novel_slug)] = novel_id
            end
        end

        if not novel_slug then
            Log("Could not determine novel slug.")
            return nil
        end
        -- Ensure novel_id is fetched if not available from list data
        if not novel_id then
            novel_id = getNovelIdFromSlug(novel_slug)
        end

        local doc = GETDocument(expandURL(novel_slug, 1))
        if not doc then
            return nil
        end

        local titleElem = doc:selectFirst(".novel-title > h1:nth-child(1)")
        local coverImgElem = doc:selectFirst(".novel-img > img:nth-child(1)")
        local descriptionElem = doc:selectFirst("#synopsis > div.content")
        local authorElem = doc:selectFirst(".novel-author > div:nth-child(2)")
        local statusElem = doc:selectFirst(".novel-status > div:nth-child(2)")

        local genres = {}
        for g_elem in doc:select(".genre-info .items span"):all() do
            table.insert(genres, g_elem:text())
        end
        if #genres == 0 and api_novel_data_from_list and api_novel_data_from_list.genres then
            for _, g_name in ipairs(api_novel_data_from_list.genres) do -- Assuming .genres is now array of strings
                table.insert(genres, g_name)
            end
        end

        local tags = {}
        for t_elem in doc:select(".tag-info .items span"):all() do
            table.insert(tags, t_elem:text())
        end

        local statusText = statusElem and statusElem:text():lower() or ""
        local novelStatus = NovelStatus.UNKNOWN
        if statusText:find("ongoing") then
            novelStatus = NovelStatus.PUBLISHING
        end
        if statusText:find("completed") then
            novelStatus = NovelStatus.COMPLETED
        end
        if statusText:find("hiatus") then
            novelStatus = NovelStatus.PAUSED
        end

        local novelInfo = NovelInfo {
            title = titleElem and titleElem:text() or novel_slug,
            imageURL = coverImgElem and (coverImgElem:attr("src") or parseSrcSet(coverImgElem:attr("srcset"))) or
                (api_novel_data_from_list and constructImageURL(
                    api_novel_data_from_list.imageURL:gsub(cdnBaseURL:gsub("{W}", "[^/]+"):gsub("{H}", "[^/]+"), "")
                        :gsub("@webp", ""), 300, 400)), -- Try to extract raw path if full URL given
            description = descriptionElem and HTMLToString(descriptionElem:html()),
            authors = authorElem and {authorElem:text()} or nil,
            status = novelStatus,
            genres = genres,
            tags = tags,
            link = novel_slug,
            id_for_extension = novel_id
        }

        if loadChapters then
            if not novel_id then
                Log("Novel ID is nil, cannot load chapters for slug: " .. novel_slug)
                novelInfo:setChapters(AsList({}))
                return novelInfo
            end

            local allChapters = {}
            local currentPage = 1
            local totalPages = 1

            while currentPage <= totalPages do
                local chapterApiResponse = makeApiRequest("/chapter/all/" .. tostring(novel_id), {
                    page = currentPage,
                    limit = 100
                }) -- limit=100 default by site
                if not chapterApiResponse or not chapterApiResponse._data then
                    Log("Failed to fetch chapters page " .. currentPage .. " for novel ID " .. novel_id)
                    break
                end

                if #chapterApiResponse._data == 0 and currentPage > 1 then
                    break
                end

                for _, chapData in ipairs(chapterApiResponse._data) do
                    table.insert(allChapters, NovelChapter {
                        order = chapData.index,
                        title = chapData.title,
                        link = novel_slug .. "/" .. chapData.slug,
                        release = chapData.created_at
                    })
                end

                if chapterApiResponse._extra and chapterApiResponse._extra._pagination then
                    totalPages = chapterApiResponse._extra._pagination._last or totalPages
                    if currentPage >= totalPages then
                        break
                    end
                elseif #chapterApiResponse._data == 0 then
                    break
                end
                currentPage = currentPage + 1
            end

            table.sort(allChapters, function(a, b)
                return (a.order or 0) < (b.order or 0)
            end)
            novelInfo:setChapters(AsList(allChapters))
        end
        return novelInfo
    end,

    getPassage = function(shrunk_chapter_url)
        local full_url = expandURL(shrunk_chapter_url, 2)
        local doc = GETDocument(full_url)
        if not doc then
            return nil
        end

        local chapterTitleElem = doc:selectFirst(".chapter-title > h2:nth-child(1)")
        local chapterTitle = chapterTitleElem and chapterTitleElem:text() or "Chapter"

        local contentContainer = doc:selectFirst(".chapter-content > div[data-v-27111477] + div[data-v-27111477]")
        if not contentContainer then
            contentContainer = doc:selectFirst(".chapter-content")
            if not contentContainer then
                return "Chapter content not found."
            end
        end

        local cleanedContent = ""
        local tempDiv = Document "" -- Create a temporary document/element to build cleaned content

        for node in contentContainer:childNodes():all() do
            if node:isElement() then
                local elem = node:asElement()
                if not elem:hasClass("ad-slot") and
                    not (elem:tagName() == "div" and elem:attr("style"):match("min-height:310px")) then
                    tempDiv:append(elem:outerHtml())
                end
            elseif node:isTextNode() then
                tempDiv:append(node:text())
            end
        end

        cleanedContent = "<h1>" .. chapterTitle .. "</h1>" .. tempDiv:html()

        return pageOf(cleanedContent, false, css) -- pageOf expects raw HTML string
    end
}
