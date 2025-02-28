local icon_set = require('ide.icons.icon_set')

local NerdIconSet = {}

local prototype = {
    icons = {
        Account        = '',
        Array          = "",
        Bookmark       = "",
        Boolean        = "",
        Calendar       = '',
        Check          = '',
        CheckAll       = '',
        Circle         = '',
        CircleFilled   = '',
        CirclePause    = '',
        CircleSlash    = '',
        CircleStop     = '',
        Class          = "ﴯ",
        Collapsed      = "",
        Color          = "",
        Comment        = '',
        Constant       = "",
        Constructor    = "",
        DiffAdded      = '',
        Enum           = "",
        EnumMember     = "",
        Event          = "",
        Expanded       = "",
        Field          = "ﰠ",
        File           = "",
        Folder         = "",
        Function       = "",
        GitBranch      = '',
        GitCommit      = 'ﰖ',
        GitCompare     = '',
        GitIssue       = '',
        GitMerge       = 'שּׁ',
        GitPullRequest = '',
        GitRepo        = '',
        IndentGuide    = "⎸",
        Info           = '',
        Interface      = "",
        Key            = "",
        Keyword        = "",
        Method         = "",
        Module         = "",
        MultiComment   = '',
        Namespace      = "",
        Notebook       = "ﴬ",
        Null           = "ﳠ",
        Number         = "",
        Object         = "",
        Operator       = "",
        Package        = "",
        Pass           = '',
        PassFilled     = '',
        Pencil         = '',
        Property       = "ﰠ",
        Reference      = "",
        Separator      = "•",
        Snippet        = "",
        Space          = " ",
        String         = "",
        Struct         = "פּ",
        Text           = "",
        Terminal       = "",
        TypeParameter  = "",
        Unit           = "塞",
        Value          = "",
        Variable       = "",
    }
}

NerdIconSet.new = function()
    local self = icon_set.new()
    self.icons = prototype.icons
    return self
end

return NerdIconSet
