-- {"id":1403038472,"ver":"1.1.1","libVer":"1.0.0","author":"JFronny","dep":["XenForo>=1.0.1"]}

local site = Require("XenForo")("https://forums.spacebattles.com/", {
    id = 1403038472,
    name = "SpaceBattles",
    imageURL = "https://forums.spacebattles.com/data/svg/2/1/1722951957/2022_favicon_192x192.png",
    forums = {
        {
            title = "Creative Writing",
            forum = 18
        },
        {
            title = "Original Fiction",
            forum = 48
        },
        {
            title = "Creative Writing Archives",
            forum = 40
        },
        {
            title = "Worm",
            forum = 115
        },
        {
            title = "Quests",
            forum = 240
        }
        --{
        --    title = "Quests (Story Only)",
        --    forum = 252
        --}
    }
})

local originalGetPassage = site.getPassage
site.getPassage = function(self, url)
    local doc = GETDocument(self:expandURL(url, KEY_CHAPTER_URL))
    local id = url:match("#(.+)$")
    local post = doc:selectFirst("#js-" .. id)
    if not post then return nil end

    local message = post:selectFirst(".bbWrapper")
    if not message then return nil end

    -- Clean up unwanted toggle text
    for _, el in ipairs(message:select("span")) do
        local txt = el:text()
        if txt == "Click to shrink..." or txt == "Click to expand..." then
            el:remove()
        end
    end

    message:prepend("<h1>" .. post:selectFirst(".threadmarkLabel"):text() .. "</h1>")
    return pageOfElem(message, true)
end

return site
