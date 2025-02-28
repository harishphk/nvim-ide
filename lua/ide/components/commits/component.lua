local base = require('ide.panels.component')
local tree = require('ide.trees.tree')
local ds_buf = require('ide.buffers.doomscrollbuffer')
local diff_buf = require('ide.buffers.diffbuffer')
local git = require('ide.lib.git.client').new()
local gitutil = require('ide.lib.git.client')
local commitnode = require('ide.components.commits.commitnode')
local commands = require('ide.components.commits.commands')
local libwin = require('ide.lib.win')
local logger = require('ide.logger.logger')
local icons = require('ide.icons')

local CommitsComponent = {}

local config_prototype = {
    default_height = nil,
    disabled_keymaps = false,
    keymaps = {
        expand = "zo",
        collapse = "zc",
        collapse_all = "zM",
        checkout = "c",
        diff = "<CR>",
        diff_split = "s",
        diff_vsplit = "v",
        diff_tab = "t",
        refresh = "r",
        hide = "<C-[>",
        close = "X",
        details = "d",
        maximize = "+",
        minimize = "-",

        -- deprecated, here for backwards compat
        jump = "<CR>",
        jump_split = "s",
        jump_vsplit = "v",
        jump_tab = "t",
    },
}

-- CommitsComponent is a derived @Component implementing a tree of incoming
-- or outgoing calls.
-- Must implement:
--  @Component.open
--  @Component.post_win_create
--  @Component.close
--  @Component.get_commands
CommitsComponent.new = function(name, config)
    -- extends 'ide.panels.Component' fields.
    local self = base.new(name)

    -- a @Tree containing the current buffer's document symbols.
    self.tree = tree.new("commits")

    -- a logger that will be used across this class and its base class methods.
    self.logger = logger.new("commits")

    -- seup config, use default and merge in user config if not nil
    self.config = vim.deepcopy(config_prototype)
    if config ~= nil then
        self.config = vim.tbl_deep_extend("force", config_prototype, config)
    end

    -- a map of file names to the number of commits to skip to obtain the next
    -- page.
    self.paging = {}

    -- keep track of last created commits, and don't refresh listing
    self.last_commits = ""

    self.hidden = false

    function self.marshal_tree(cb)
        git.head(function(head)
            self.tree.walk_subtree(self.tree.root, function(node)
                if gitutil.compare_sha(head, node.sha) then
                    node.is_head = true
                else
                    node.is_head = false
                end
                return true
            end)
            self.tree.marshal({ no_guides_leafs = true, virt_text_pos = "eol" })
            if cb ~= nil then
                cb()
            end
        end)
    end

    -- The callback used to load more git commits into the Commits when the
    -- bottom of the buffer is hit.
    function self.doomscroll(Buffer)
        if self.tree.root == nil then
            return
        end
        local name = self.tree.root.subject
        if name == nil or name == "" then
            return
        end
        vim.notify("loading more commits...", vim.log.levels.INFO)
        git.log_commits(self.paging[name], 25, function(commits)
            if commits == nil then
                return
            end
            if #commits == 0 then
                return
            end
            local children = {}
            for _, commit in ipairs(commits) do
                local node = commitnode.new(commit.sha, name, commit.subject, commit.author, commit.date)
                table.insert(children, node)
            end
            self.tree.add_node(self.tree.root, children, { append = true })
            self.marshal_tree(function()
                if #children > 0 then
                    self.paging[name] = self.paging[name] + 25
                end
                self.state["cursor"].restore()
            end)
        end)
    end

    -- Use a doomscrollbuffer to load more commits when the cursor hits
    -- the bottom of the buffer.
    self.buffer = ds_buf.new(self.doomscroll, nil, false, true)

    local function setup_buffer()
        local log = self.logger.logger_from(nil, "Component._setup_buffer")
        local buf = self.buffer.buf

        vim.api.nvim_buf_set_option(buf, 'bufhidden', 'hide')
        vim.api.nvim_buf_set_option(buf, 'filetype', 'filetree')
        vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
        vim.api.nvim_buf_set_option(buf, 'modifiable', false)
        vim.api.nvim_buf_set_option(buf, 'swapfile', false)
        vim.api.nvim_buf_set_option(buf, 'textwidth', 0)
        vim.api.nvim_buf_set_option(buf, 'wrapmargin', 0)

        if not self.config.disable_keymaps then
            vim.api.nvim_buf_set_keymap(buf, "n", self.config.keymaps.expand, "",
                { silent = true, callback = function() self.expand() end })
            vim.api.nvim_buf_set_keymap(buf, "n", self.config.keymaps.collapse, "",
                { silent = true, callback = function() self.collapse() end })
            vim.api.nvim_buf_set_keymap(buf, "n", self.config.keymaps.collapse_all, "",
                { silent = true, callback = function() self.collapse_all() end })
            vim.api.nvim_buf_set_keymap(buf, "n", self.config.keymaps.checkout, "",
                { silent = true, callback = function() self.checkout_commitnode({ fargs = {} }) end })
            vim.api.nvim_buf_set_keymap(buf, "n", self.config.keymaps.diff, "",
                { silent = true, callback = function() self.diff({ fargs = {} }) end })
            vim.api.nvim_buf_set_keymap(buf, "n", self.config.keymaps.diff_tab, "",
                { silent = true, callback = function() self.diff({ fargs = { "tab" } }) end })
            vim.api.nvim_buf_set_keymap(buf, "n", self.config.keymaps.refresh, "",
                { silent = true, callback = function() self.get_commits() end })
            vim.api.nvim_buf_set_keymap(buf, "n", self.config.keymaps.hide, "",
                { silent = true, callback = function() self.hide() end })
            vim.api.nvim_buf_set_keymap(buf, "n", self.config.keymaps.details, "",
                { silent = true, callback = function() self.details() end })
            vim.api.nvim_buf_set_keymap(buf, "n", self.config.keymaps.maximize, "", { silent = true,
                callback = self.maximize })
            vim.api.nvim_buf_set_keymap(buf, "n", self.config.keymaps.minimize, "", { silent = true,
                callback = self.minimize })

            -- deprecated, here for backwards compat
            vim.api.nvim_buf_set_keymap(buf, "n", self.config.keymaps.jump, "",
                { silent = true, callback = function() self.diff({ fargs = {} }) end })
            vim.api.nvim_buf_set_keymap(buf, "n", self.config.keymaps.jump_tab, "",
                { silent = true, callback = function() self.diff({ fargs = { "tab" } }) end })
        end

        return buf
    end

    self.buf = setup_buffer()

    self.tree.set_buffer(self.buf)

    -- implements @Component.open()
    function self.open()
        if self.tree.root == nil then
            self.get_commits()
        end
        return self.buf
    end

    -- implements @Component interface
    function self.post_win_create()
        local log = self.logger.logger_from(nil, "Component.post_win_create")
        icons.global_icon_set.set_win_highlights()
    end

    -- implements @Component interface
    function self.get_commands()
        log = self.logger.logger_from(nil, "Component.get_commands")
        return commands.new(self).get()
    end

    -- implements optional @Component interface
    -- Expand the @CallNode at the current cursor location
    --
    -- @args - @table, user command table as described in ":h nvim_create_user_command()"
    -- @commitnode - @CallNode, an override which expands the given @CallNode, ignoring the
    --             node under the current position.
    function self.expand(args, commitnode)
        local log = self.logger.logger_from(nil, "Component.expand")
        if not libwin.win_is_valid(self.win) then
            return
        end
        if commitnode == nil then
            commitnode = self.tree.unmarshal(self.state["cursor"].cursor[1])
            if commitnode == nil then
                return
            end
        end
        commitnode.expand(function()
            self.marshal_tree(function()
                self.state["cursor"].restore()
            end)
        end)
    end

    -- Collapse the @CallNode at the current cursor location
    --
    -- @args - @table, user command table as described in ":h nvim_create_user_command()"
    -- @commitnode - @CallNode, an override which collapses the given @CallNode, ignoring the
    --           node under the current position.
    function self.collapse(args, commitnode)
        local log = self.logger.logger_from(nil, "Component.collapse")
        if not libwin.win_is_valid(self.win) then
            return
        end
        if commitnode == nil then
            commitnode = self.tree.unmarshal(self.state["cursor"].cursor[1])
            if commitnode == nil then
                return
            end
        end
        self.tree.collapse_subtree(commitnode)

        self.marshal_tree(function()
            self.state["cursor"].restore()
        end)
    end

    -- Collapse the call hierarchy up to the root.
    --
    -- @args - @table, user command table as described in ":h nvim_create_user_command()"
    function self.collapse_all(args)
        local log = self.logger.logger_from(nil, "Component.collapse_all")
        if not libwin.win_is_valid(self.win) then
            return
        end
        if commitnode == nil then
            commitnode = self.tree.unmarshal(self.state["cursor"].cursor[1])
            if commitnode == nil then
                return
            end
        end
        self.tree.collapse_subtree(self.tree.root)
        self.marshal_tree(function()
            self.state["cursor"].restore()
        end)
    end

    function self.get_commits()
        git.if_in_git_repo(function()
            if not gitutil.repo_has_commits() then
                return
            end
            local cur_tab = vim.api.nvim_get_current_tabpage()
            if self.workspace.tab ~= cur_tab then
                return
            end
            local repo = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
            git.log_commits(0, 25, function(commits)
                if commits == nil then
                    return
                end
                local children = {}
                for _, commit in ipairs(commits) do
                    local node = commitnode.new(commit.sha, commit.sha, commit.subject, commit.author, commit.date)
                    table.insert(children, node)
                end
                local root = commitnode.new("", "", repo, "", "", 0)
                self.tree.add_node(root, children)

                self.marshal_tree(function()
                    self.paging[repo] = 25
                    self.last_commits = name
                end)
            end)
        end)
    end

    function self.checkout_commitnode(args)
        if not gitutil.in_git_repo() then
            vim.notify("Must be in a git repo to checkout commits", "error", {
                title = "Commits",
            })
            return
        end
        local log = self.logger.logger_from(nil, "Component.jump_commitnode")

        local node = self.tree.unmarshal(self.state["cursor"].cursor[1])
        if node == nil then
            return
        end

        local commit = node
        if node.is_file then
            commit = node.parent
        end

        local function do_diff(file_a, sha_a, path)
            local buf_name_a = string.format("diff://%d/%s/%s", vim.fn.rand(), sha_a, path)

            local tab = false
            for _, arg in ipairs(args.fargs) do
                if arg == "tab" then
                    tab = true
                end
            end

            if tab then
                vim.cmd("tabnew")
            end

            local dbuff = diff_buf.new()
            dbuff.setup()
            local o = { listed = false, scratch = true, modifiable = false }
            dbuff.write_lines(file_a, "a", o)

            if vim.fn.glob(path) == "" then
                dbuff.write_lines({ "" }, "b", o)
            else
                dbuff.open_buffer(path, "b")
            end

            dbuff.buffer_a.set_name(buf_name_a)
            dbuff.diff()
        end

        local function _resolve_diff()
            -- we need to find the parent node, but this is a list where all commits
            -- are at depth one,
            local _, i = self.tree.depth_table.search(commit.depth, commit.key)
            if i == nil then
                error("failed to find index of node in depth table")
            end
            local pcommit = self.tree.depth_table.table[commit.depth][i + 1]
            if pcommit ~= nil then
                git.show_file(pcommit.sha, node.file, function(file)
                    do_diff(file, pcommit.sha, node.file)
                    self.marshal_tree()
                end)
            else
                do_diff({}, "null", node.file)
                self.marshal_tree()
            end
        end

        if not node.is_file then
            return
        end

        -- commit is already head, don't do the checkout.
        if commit.is_head then
            _resolve_diff()
            return
        end

        -- checkout the commit so all the LSP tools work when viewing the diff.
        git.checkout(commit.sha, function(ok)
            if ok == nil then
                return
            end
            _resolve_diff()
        end)
    end

    function self.diff(args)
        local log = self.logger.logger_from(nil, "Component.jump_commitnode")

        local node = self.tree.unmarshal(self.state["cursor"].cursor[1])
        if node == nil then
            return
        end
        if not node.is_file then
            return
        end
        local commit = node.parent

        -- we need to find the parent node, but this is a list where all commits
        -- are at depth one,
        local _, i = self.tree.depth_table.search(commit.depth, commit.key)
        if i == nil then
            error("failed to find index of node in depth table")
        end
        local pcommit = self.tree.depth_table.table[commit.depth][i + 1]

        function _do_tabnew()
            local tab = false
            for _, arg in ipairs(args.fargs) do
                if arg == "tab" then
                    tab = true
                end
            end

            if tab then
                vim.cmd("tabnew")
            end
        end

        local function do_diff(file_a, file_b, sha_a, sha_b, path)
            local buf_name_a = string.format("diff://%d/%s/%s", vim.fn.rand(), sha_a, path)
            local buf_name_b = string.format("diff://%d/%s/%s", vim.fn.rand(), sha_b, path)

            _do_tabnew()

            local dbuff = diff_buf.new()
            dbuff.setup()
            local o = { listed = false, scratch = true, modifiable = false }
            dbuff.write_lines(file_a, "a", o)
            dbuff.write_lines(file_b, "b", o)

            dbuff.buffer_a.set_name(buf_name_a)
            dbuff.buffer_b.set_name(buf_name_b)
            dbuff.diff()
        end

        local function do_diff_local(file_a, buffer_b, sha_a, path)
            local buf_name_a = string.format("diff://%d/%s/%s", vim.fn.rand(), sha_a, path)

            _do_tabnew()

            local dbuff = diff_buf.new()
            dbuff.setup()
            local o = { listed = false, scratch = true, modifiable = false }
            dbuff.write_lines(file_a, "a", o)
            dbuff.open_buffer(buffer_b, "b")
            dbuff.buffer_a.set_name(buf_name_a)
            dbuff.diff()
        end

        git.show_file(pcommit.sha, node.file, function(file_a)
            if file_a == nil then
                return
            end
            if commit.is_head then
                -- if the commit is the current commit, we can open the the local
                -- file
                do_diff_local(file_a, node.file, pcommit.sha, node.file)
                return
            end
            git.show_file(node.sha, node.file, function(file_b)
                if file_b == nil then
                    return
                end
                do_diff(file_a, file_b, pcommit.sha, node.sha, node.file)
            end)
        end)
    end

    function self.details(args)
        local log = self.logger.logger_from(nil, "Component.details")

        local node = self.tree.unmarshal(self.state["cursor"].cursor[1])
        if node == nil then
            return
        end

        if node.depth == 0 then
            return
        end

        node.details()
    end

    return self
end

return CommitsComponent
