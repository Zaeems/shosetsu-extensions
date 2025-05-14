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
    local page = originalGetPassage(self, url)
    if not page then return nil end

    -- Try to detect and clean HTML if possible
    local success, html = pcall(function()
        return page:html and page:html()
    end)

    if success and html and type(html) == "string" then
        html = html:gsub("Click to shrink%.%.%.", "")
        html = html:gsub("Click to expand%.%.%.", "")
        if page.setHTML then
            page:setHTML(html)
        end
        return page
    end

    -- Fallback: look for a `content` field and clean it
    if type(page) == "table" and type(page.content) == "string" then
        page.content = page.content
            :gsub("Click to shrink%.%.%.", "")
            :gsub("Click to expand%.%.%.", "")
        return page
    end

    -- Final fallback: return as-is if no modification possible
    return page
end


return site
