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

    local html = page:html()
    html = html:gsub("Click here to shrink%.%.%.", "")
    html = html:gsub("Click here to expand%.%.%.", "")
    page:setHTML(html)

    return page
end

return site
