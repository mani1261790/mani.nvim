-- =========================================================
-- VS Code-like Neovim (single-file config)
-- Neo-tree (left) + ToggleTerm/Aider (bottom) + Telescope + LSP + Completion
-- Neovim 0.11+ LSP style: vim.lsp.config / vim.lsp.enable
-- =========================================================

-- Leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

local preferred_python = vim.fn.exepath("python3.11")
if preferred_python == "" then
  preferred_python = vim.fn.exepath("python3.13")
end
if preferred_python == "" then
  preferred_python = vim.fn.exepath("python3")
end

local python_version_suffix = preferred_python:match("python(%d+%.%d+)$") or "3.9"
local python_host_bin = vim.fs.dirname(preferred_python)
local python_user_bin = vim.fn.expand("~/Library/Python/" .. python_version_suffix .. "/bin")

for _, path in ipairs({ python_user_bin, python_host_bin }) do
  if path ~= "" and vim.fn.isdirectory(path) == 1 and not vim.env.PATH:find(vim.pesc(path), 1, true) then
    vim.env.PATH = path .. ":" .. vim.env.PATH
  end
end

vim.g.python3_host_prog = preferred_python

-- Basic UI
vim.opt.laststatus = 3
vim.opt.pumblend = 10
vim.opt.winblend = 0
vim.opt.showmode = false
vim.opt.cmdheight = 0

vim.opt.number = true
vim.opt.relativenumber = false
vim.opt.termguicolors = true
vim.opt.signcolumn = "yes"
vim.opt.cursorline = true
vim.opt.wrap = false
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8

vim.cmd("syntax enable")
vim.opt.termguicolors = true

vim.opt.mouse = "a"
vim.opt.mousescroll = "ver:2,hor:4"
vim.opt.scrolloff = 5
vim.opt.scrollback = 2000

vim.opt.linespace = 6
vim.opt.guicursor = "n-v:block,o:block,c:block,i-ci-ve-t:ver25,r-cr:hor20"
vim.opt.cursorline = true
vim.opt.colorcolumn = ""
vim.opt.list = true
vim.opt.listchars = {
  tab = "  ",
  trail = "·",
  extends = "›",
  precedes = "‹",
}
vim.opt.mouse = "a"
vim.opt.mousescroll = "ver:2,hor:2"

vim.opt.fillchars = {
  vert = "│",
  horiz = "─",
  horizup = "┴",
  horizdown = "┬",
  vertleft = "┤",
  vertright = "├",
  verthoriz = "┼",
}

-- Indent
vim.opt.expandtab = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.smartindent = true

-- Search
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.incsearch = true

-- Clipboard
vim.opt.clipboard = "unnamedplus"

-- Faster UI
vim.opt.updatetime = 300
vim.opt.timeoutlen = 400

-- Remove intro screen
vim.opt.shortmess:append("I")

-- Splits
vim.opt.splitright = true
vim.opt.splitbelow = true

local large_file_threshold = 1024 * 1024

local function is_large_file(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return false
  end

  local ok, stat = pcall(vim.uv.fs_stat, name)
  return ok and stat and stat.size and stat.size > large_file_threshold or false
end

vim.api.nvim_create_autocmd("BufReadPre", {
  callback = function(args)
    if not is_large_file(args.buf) then
      return
    end

    vim.b[args.buf].large_file = true
    vim.bo[args.buf].swapfile = false
    vim.bo[args.buf].undofile = false
  end,
})

local function is_sidebar_window(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  return vim.bo[buf].filetype == "neo-tree"
end

local function is_terminal_window(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local name = vim.api.nvim_buf_get_name(buf)
  local buftype = vim.bo[buf].buftype
  local filetype = vim.bo[buf].filetype
  return buftype == "terminal" or filetype == "toggleterm" or name:match("^term://") ~= nil
end

local terminal_sidebar = {
  buf = nil,
  win = nil,
  height = 15,
  actions = {},
  term_ids = {},
}

local terminal_panel = {
  win = nil,
  height = 15,
}

local find_sidebar_window
local get_toggleterm_api
local get_toggleterm_ui
local close_terminal_by_id
local open_named_terminal
local open_new_terminal

local function is_edit_window(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == "" and vim.bo[buf].filetype ~= "neo-tree"
end

local function count_edit_windows()
  local count = 0
  local last_edit_win = nil

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_edit_window(win) then
      count = count + 1
      last_edit_win = win
    end
  end

  return count, last_edit_win
end

local function create_layout_placeholder_buffer()
  local scratch = vim.api.nvim_create_buf(false, true)
  vim.bo[scratch].buftype = "nofile"
  vim.bo[scratch].bufhidden = "wipe"
  vim.bo[scratch].buflisted = false
  vim.bo[scratch].swapfile = false
  vim.bo[scratch].modifiable = false
  return scratch
end

local function preserve_layout_before_bdelete(bufnr)
  local edit_count, edit_win = count_edit_windows()
  if edit_count ~= 1 or not edit_win or not vim.api.nvim_win_is_valid(edit_win) then
    return
  end

  if vim.api.nvim_win_get_buf(edit_win) ~= bufnr then
    return
  end

  local scratch = create_layout_placeholder_buffer()
  vim.api.nvim_win_set_buf(edit_win, scratch)
end

local function smart_bdelete(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not bufnr or bufnr == 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if vim.bo[bufnr].buftype == "" and vim.bo[bufnr].filetype ~= "neo-tree" then
    preserve_layout_before_bdelete(bufnr)
  end

  vim.cmd(("bdelete %d"):format(bufnr))
end

local function find_edit_window()
  local current_win = vim.api.nvim_get_current_win()
  if is_edit_window(current_win) then
    return current_win
  end

  local best_win = nil
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_edit_window(win) then
      if not best_win then
        best_win = win
      else
        local best_pos = vim.api.nvim_win_get_position(best_win)
        local win_pos = vim.api.nvim_win_get_position(win)
        if win_pos[2] > best_pos[2] or (win_pos[2] == best_pos[2] and win_pos[1] < best_pos[1]) then
          best_win = win
        end
      end
    end
  end

  return best_win
end

local function ensure_edit_window()
  local edit_win = find_edit_window()
  if edit_win and vim.api.nvim_win_is_valid(edit_win) then
    return edit_win
  end

  local base_win = find_sidebar_window() or vim.api.nvim_get_current_win()
  if not base_win or not vim.api.nvim_win_is_valid(base_win) then
    return nil
  end

  local created_win = nil
  vim.api.nvim_win_call(base_win, function()
    vim.cmd("rightbelow vsplit")
    created_win = vim.api.nvim_get_current_win()
    vim.cmd("enew")
  end)

  if created_win and vim.api.nvim_win_is_valid(created_win) then
    return created_win
  end

  return find_edit_window()
end

local function ensure_terminal_sidebar_buffer()
  if terminal_sidebar.buf and vim.api.nvim_buf_is_valid(terminal_sidebar.buf) then
    return terminal_sidebar.buf
  end

  local buf = vim.api.nvim_create_buf(false, true)
  terminal_sidebar.buf = buf
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "terminal-sidebar"

  local opts = { buffer = buf, noremap = true, silent = true, nowait = true }
  local function activate_current_terminal_sidebar_item()
    local action = terminal_sidebar.actions[vim.fn.line(".")]
    if action then
      action()
    end
  end

  local function close_current_terminal_sidebar_item()
    local term_id = terminal_sidebar.term_ids[vim.fn.line(".")]
    if not term_id then
      return
    end
    close_terminal_by_id(term_id)
  end

  vim.keymap.set("n", "<CR>", activate_current_terminal_sidebar_item, opts)
  vim.keymap.set("n", "o", activate_current_terminal_sidebar_item, opts)
  vim.keymap.set("n", "<LeftMouse>", activate_current_terminal_sidebar_item, opts)
  vim.keymap.set("n", "<2-LeftMouse>", activate_current_terminal_sidebar_item, opts)
  vim.keymap.set("n", "x", close_current_terminal_sidebar_item, opts)
  vim.keymap.set("n", "d", close_current_terminal_sidebar_item, opts)
  vim.keymap.set("n", "q", "<Nop>", opts)
  vim.keymap.set("n", "zh", "<Nop>", opts)
  vim.keymap.set("n", "zl", "<Nop>", opts)
  vim.keymap.set("n", "zH", "<Nop>", opts)
  vim.keymap.set("n", "zL", "<Nop>", opts)
  vim.keymap.set("n", "zs", "<Nop>", opts)
  vim.keymap.set("n", "ze", "<Nop>", opts)
  vim.keymap.set("n", "<ScrollWheelLeft>", "<Nop>", opts)
  vim.keymap.set("n", "<ScrollWheelRight>", "<Nop>", opts)
  vim.keymap.set("n", "<S-ScrollWheelLeft>", "<Nop>", opts)
  vim.keymap.set("n", "<S-ScrollWheelRight>", "<Nop>", opts)

  return buf
end

local function render_terminal_sidebar()
  local buf = ensure_terminal_sidebar_buffer()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local toggleterm_terminal = get_toggleterm_api()
  if not toggleterm_terminal then
    return
  end

  local terms = toggleterm_terminal.get_all(true)
  table.sort(terms, function(a, b)
    return a.id < b.id
  end)

  local focused_id = toggleterm_terminal.get_focused_id()
  local lines = {
    " Terminals",
    "",
    "  [+] New Terminal",
    "",
  }
  local actions = {
    [3] = function()
      open_new_terminal()
    end,
  }
  local term_ids = {}

  for _, term in ipairs(terms) do
    if term.id ~= 99 then
      local prefix = focused_id == term.id and "> " or "  "
      local status = term:is_open() and "●" or "○"
      table.insert(lines, string.format("%s[%d] %s Terminal %d    x close", prefix, term.id, status, term.id))
      term_ids[#lines] = term.id
      actions[#lines] = function()
        open_named_terminal(term.id, term.display_name)
      end
    end
  end

  if #lines == 4 then
    table.insert(lines, "  No terminals yet")
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  terminal_sidebar.actions = actions
  terminal_sidebar.term_ids = term_ids
end

local function ensure_terminal_sidebar_panel()
  local sidebar_win = find_sidebar_window()
  if not sidebar_win or not vim.api.nvim_win_is_valid(sidebar_win) then
    return nil
  end

  local panel_buf = ensure_terminal_sidebar_buffer()
  local current_win = vim.api.nvim_get_current_win()

  if terminal_sidebar.win and vim.api.nvim_win_is_valid(terminal_sidebar.win) then
    if vim.api.nvim_win_get_buf(terminal_sidebar.win) ~= panel_buf then
      vim.api.nvim_win_set_buf(terminal_sidebar.win, panel_buf)
    end
    vim.api.nvim_win_set_height(terminal_sidebar.win, terminal_sidebar.height)
    render_terminal_sidebar()
    if vim.api.nvim_win_is_valid(current_win) then
      pcall(vim.api.nvim_set_current_win, current_win)
    end
    return terminal_sidebar.win
  end

  vim.api.nvim_win_call(sidebar_win, function()
    vim.cmd("belowright split")
    terminal_sidebar.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(terminal_sidebar.win, panel_buf)
    vim.api.nvim_win_set_height(terminal_sidebar.win, terminal_sidebar.height)
  end)

  if terminal_sidebar.win and vim.api.nvim_win_is_valid(terminal_sidebar.win) then
    vim.wo[terminal_sidebar.win].number = false
    vim.wo[terminal_sidebar.win].relativenumber = false
    vim.wo[terminal_sidebar.win].signcolumn = "no"
    vim.wo[terminal_sidebar.win].foldcolumn = "0"
    vim.wo[terminal_sidebar.win].spell = false
    vim.wo[terminal_sidebar.win].wrap = false
    vim.wo[terminal_sidebar.win].sidescrolloff = 0
    vim.wo[terminal_sidebar.win].winfixheight = true
    vim.wo[terminal_sidebar.win].cursorline = true
    vim.wo[terminal_sidebar.win].winbar = " Terminal List "
  end

  render_terminal_sidebar()

  if vim.api.nvim_win_is_valid(current_win) then
    pcall(vim.api.nvim_set_current_win, current_win)
  end

  return terminal_sidebar.win
end

local function find_terminal_list_window()
  if terminal_sidebar.win and vim.api.nvim_win_is_valid(terminal_sidebar.win) then
    return terminal_sidebar.win
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "terminal-sidebar" then
      terminal_sidebar.win = win
      return win
    end
  end
end

local function open_buffer_in_edit_window(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local target_win = ensure_edit_window()
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
    vim.api.nvim_set_current_buf(bufnr)
    return
  end

  vim.api.nvim_set_current_buf(bufnr)
end

local function open_path_in_edit_window(path)
  if not path or path == "" then
    return
  end

  local target_win = ensure_edit_window()
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_win_call(target_win, function()
      vim.cmd("drop " .. vim.fn.fnameescape(path))
    end)
    return
  end

  vim.cmd("drop " .. vim.fn.fnameescape(path))
end

local function begin_neotree_rename()
  if vim.bo.filetype ~= "neo-tree" then
    return
  end

  local ok_manager, manager = pcall(require, "neo-tree.sources.manager")
  if not ok_manager then
    return
  end

  local state = manager.get_state_for_window(vim.api.nvim_get_current_win())
  if not state or not state.name then
    return
  end

  local ok_commands, commands = pcall(require, "neo-tree.sources." .. state.name .. ".commands")
  if not ok_commands or type(commands.rename) ~= "function" then
    return
  end

  commands.rename(state)
end

find_sidebar_window = function()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_sidebar_window(win) then
      return win
    end
  end
end

local function find_terminal_window()
  local best_win = nil
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_terminal_window(win) then
      if not best_win then
        best_win = win
      else
        local best_pos = vim.api.nvim_win_get_position(best_win)
        local win_pos = vim.api.nvim_win_get_position(win)
        if win_pos[1] > best_pos[1] then
          best_win = win
        end
      end
    end
  end
  return best_win
end

local function focus_window(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
end

local function focus_sidebar()
  focus_window(find_sidebar_window())
end

local function focus_terminal_list_panel()
  focus_window(find_terminal_list_window() or ensure_terminal_sidebar_panel())
end

local function focus_code_panel()
  focus_window(ensure_edit_window())
end

local function focus_terminal_panel()
  focus_window(find_terminal_window() or terminal_panel.win)
end

get_toggleterm_api = function()
  local ok, toggleterm_terminal = pcall(require, "toggleterm.terminal")
  if not ok then
    return nil
  end

  return toggleterm_terminal
end

get_toggleterm_ui = function()
  local ok, toggleterm_ui = pcall(require, "toggleterm.ui")
  if not ok then
    return nil
  end

  return toggleterm_ui
end

local function find_toggleterm_by_buf(bufnr)
  local toggleterm_terminal = get_toggleterm_api()
  if not toggleterm_terminal then
    return nil
  end

  return toggleterm_terminal.find(function(term)
    return term.bufnr == bufnr
  end)
end

local function focus_toggleterm_buffer(bufnr)
  local term = find_toggleterm_by_buf(bufnr)
  if term then
    if term:is_open() then
      term:focus()
    else
      open_named_terminal(term.id, term.display_name)
    end
    return
  end

  open_buffer_in_edit_window(bufnr)
end

local function next_terminal_id()
  local toggleterm_terminal = get_toggleterm_api()
  if not toggleterm_terminal then
    return 1
  end

  local next_id = 1
  for _, term in ipairs(toggleterm_terminal.get_all(true)) do
    if term.id ~= 99 then
      next_id = math.max(next_id, term.id + 1)
    end
  end

  return next_id
end

local function open_terminal_in_edit_column(term)
  local target_win = ensure_edit_window()
  if not target_win or not vim.api.nvim_win_is_valid(target_win) then
    return
  end

  local toggleterm_ui = get_toggleterm_ui()
  if toggleterm_ui then
    toggleterm_ui.set_origin_window()
  end

  local terminal_win = terminal_panel.win
  if not terminal_win or not vim.api.nvim_win_is_valid(terminal_win) then
    vim.api.nvim_win_call(target_win, function()
      vim.cmd("rightbelow split")
      terminal_win = vim.api.nvim_get_current_win()
      vim.cmd("resize " .. terminal_panel.height)
    end)
    terminal_panel.win = terminal_win
  else
    vim.api.nvim_win_set_height(terminal_win, terminal_panel.height)
  end

  if not terminal_win or not vim.api.nvim_win_is_valid(terminal_win) then
    return
  end

  term.window = terminal_win

  if term.bufnr and vim.api.nvim_buf_is_valid(term.bufnr) then
    vim.api.nvim_win_set_buf(terminal_win, term.bufnr)
    term:__resurrect()
  else
    term.bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_win_set_buf(terminal_win, term.bufnr)
    term:__set_options()
    term:spawn()
    if toggleterm_ui then
      toggleterm_ui.hl_term(term)
    end
  end

  if term.on_open then
    term:on_open()
  end

  vim.api.nvim_set_current_win(terminal_win)
  vim.cmd("startinsert")
end

close_terminal_by_id = function(term_id)
  local toggleterm_terminal = get_toggleterm_api()
  if not toggleterm_terminal then
    return
  end

  local term = toggleterm_terminal.get(term_id, true)
  if not term then
    return
  end

  local was_visible = false
  if terminal_panel.win and vim.api.nvim_win_is_valid(terminal_panel.win) then
    was_visible = vim.api.nvim_win_get_buf(terminal_panel.win) == term.bufnr
    if was_visible then
      local scratch = create_layout_placeholder_buffer()
      vim.api.nvim_win_set_buf(terminal_panel.win, scratch)
    end
  end

  term:shutdown()

  if was_visible then
    local remaining = toggleterm_terminal.get_all()
    table.sort(remaining, function(a, b)
      return a.id < b.id
    end)

    if #remaining > 0 then
      open_named_terminal(remaining[1].id, remaining[1].display_name)
    end
  end

  render_terminal_sidebar()
end

open_named_terminal = function(id, display_name)
  local toggleterm_terminal = get_toggleterm_api()
  if not toggleterm_terminal then
    return
  end

  local term = toggleterm_terminal.get(id, true)
  if not term then
    term = toggleterm_terminal.Terminal:new({
      count = id,
      direction = "horizontal",
      size = 15,
      close_on_exit = false,
      display_name = display_name or ("Terminal " .. id),
    })
  elseif display_name and not term.display_name then
    term.display_name = display_name
  end

  if term:is_open() then
    term:focus()
  else
    open_terminal_in_edit_column(term)
  end

  ensure_terminal_sidebar_panel()
  render_terminal_sidebar()

  return term
end

local function close_current_terminal()
  local term = find_toggleterm_by_buf(vim.api.nvim_get_current_buf())
  if term then
    close_terminal_by_id(term.id)
  end
end

local function toggle_primary_terminal()
  local current_term = find_toggleterm_by_buf(vim.api.nvim_get_current_buf())
  if current_term and current_term:is_open() then
    current_term:close()
    render_terminal_sidebar()
    return
  end

  local toggleterm_terminal = get_toggleterm_api()
  if not toggleterm_terminal then
    return
  end

  local target = nil
  local focused_id = toggleterm_terminal.get_focused_id()
  if focused_id then
    target = toggleterm_terminal.get(focused_id, true)
  end

  if not target then
    target = toggleterm_terminal.get_last_focused()
  end

  if not target then
    local terms = toggleterm_terminal.get_all()
    target = terms[1]
  end

  if target then
    open_named_terminal(target.id, target.display_name)
    return
  end

  open_named_terminal(1, "Terminal 1")
end

open_new_terminal = function()
  local id = next_terminal_id()
  open_named_terminal(id, "Terminal " .. id)
end

local function open_terminal_slot(id)
  open_named_terminal(id, "Terminal " .. id)
end

local function restart_nvim_in_place()
  local cwd = vim.fn.getcwd()
  local current_file = ""
  local current_buf = vim.api.nvim_get_current_buf()
  if vim.bo[current_buf].buftype == "" then
    current_file = vim.api.nvim_buf_get_name(current_buf)
  end

  local toggleterm_terminal = get_toggleterm_api()
  local target_term = nil
  if toggleterm_terminal then
    local focused_id = toggleterm_terminal.get_focused_id()
    if focused_id then
      target_term = toggleterm_terminal.get(focused_id, true)
    end
    if not target_term then
      target_term = toggleterm_terminal.get_last_focused()
    end
    if not target_term then
      local terms = toggleterm_terminal.get_all()
      target_term = terms[1]
    end
  end

  local edit_win = ensure_edit_window() or vim.api.nvim_get_current_win()
  if edit_win and vim.api.nvim_win_is_valid(edit_win) then
    vim.api.nvim_set_current_win(edit_win)
  end

  pcall(vim.cmd, "silent! wall")
  vim.cmd("silent! only")
  vim.cmd("silent! cd " .. vim.fn.fnameescape(cwd))

  if current_file ~= "" and vim.fn.filereadable(current_file) == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(current_file))
  end

  vim.cmd("Neotree show")
  ensure_terminal_sidebar_panel()

  if target_term then
    open_named_terminal(target_term.id, target_term.display_name)
  else
    open_named_terminal(1, "Terminal 1")
  end
end

local function cycle_toggleterm(offset)
  local toggleterm_terminal = get_toggleterm_api()
  if not toggleterm_terminal then
    return
  end

  local terms = toggleterm_terminal.get_all()
  if #terms == 0 then
    open_named_terminal(1, "Terminal 1")
    return
  end

  table.sort(terms, function(a, b)
    return a.id < b.id
  end)

  local current_id = toggleterm_terminal.get_focused_id()
  if not current_id then
    local last = toggleterm_terminal.get_last_focused()
    current_id = last and last.id or nil
  end

  local current_index = 1
  for index, term in ipairs(terms) do
    if term.id == current_id then
      current_index = index
      break
    end
  end

  local target_index = ((current_index - 1 + offset) % #terms) + 1
  local target = terms[target_index]

  open_named_terminal(target.id, target.display_name)
end

local function cycle_main_panes()
  local current_win = vim.api.nvim_get_current_win()
  local order = { find_terminal_window() or terminal_panel.win, find_terminal_list_window(), find_sidebar_window(), find_edit_window() }
  local valid = {}

  for _, win in ipairs(order) do
    if win and vim.api.nvim_win_is_valid(win) then
      table.insert(valid, win)
    end
  end

  for index, win in ipairs(valid) do
    if win == current_win then
      focus_window(valid[(index % #valid) + 1])
      return
    end
  end

  focus_window(valid[1])
end

local function cycle_main_panes_reverse()
  local current_win = vim.api.nvim_get_current_win()
  local order = { find_terminal_window() or terminal_panel.win, find_terminal_list_window(), find_sidebar_window(), find_edit_window() }
  local valid = {}

  for _, win in ipairs(order) do
    if win and vim.api.nvim_win_is_valid(win) then
      table.insert(valid, win)
    end
  end

  for index, win in ipairs(valid) do
    if win == current_win then
      local prev = index - 1
      if prev < 1 then
        prev = #valid
      end
      focus_window(valid[prev])
      return
    end
  end

  focus_window(valid[#valid])
end

local suppress_terminal_reentry = false

local function leave_terminal_and(run)
  suppress_terminal_reentry = true
  vim.cmd("stopinsert")
  vim.schedule(function()
    run()
    vim.schedule(function()
      suppress_terminal_reentry = false
    end)
  end)
end

local function set_hl_italic(name, italic)
  local ok, current = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if not ok or not current or vim.tbl_isempty(current) then
    return
  end

  current.italic = italic
  current.force = true
  vim.api.nvim_set_hl(0, name, current)
end

local function update_bufferline_mode_highlight()
  local italic = not vim.api.nvim_get_mode().mode:match("^i")
  local groups = {
    "BufferLineBufferSelected",
    "BufferLineNumbersSelected",
    "BufferLineDiagnosticSelected",
    "BufferLineCloseButtonSelected",
    "BufferLineModifiedSelected",
    "BufferLineDuplicateSelected",
    "BufferLineHintSelected",
    "BufferLineHintDiagnosticSelected",
    "BufferLineInfoSelected",
    "BufferLineInfoDiagnosticSelected",
    "BufferLineWarningSelected",
    "BufferLineWarningDiagnosticSelected",
    "BufferLineErrorSelected",
    "BufferLineErrorDiagnosticSelected",
  }

  for _, group in ipairs(groups) do
    set_hl_italic(group, italic)
  end
end

local bufferline_mode_ui = vim.api.nvim_create_augroup("bufferline-mode-ui", { clear = true })

vim.api.nvim_create_autocmd({ "InsertEnter", "InsertLeave", "ModeChanged", "ColorScheme", "VimEnter" }, {
  group = bufferline_mode_ui,
  callback = function()
    vim.schedule(update_bufferline_mode_highlight)
  end,
})

local function git_branch_name()
  local head = vim.b.gitsigns_head
  if head and head ~= "" then
    return head
  end

  if vim.b.fugitive_head and vim.b.fugitive_head ~= "" then
    return vim.b.fugitive_head
  end

  return ""
end

local function git_statusline_component()
  local branch = git_branch_name()
  if branch == "" then
    return ""
  end

  return "  git:" .. branch .. " "
end

local function notebook_default_kernel()
  local kernel = vim.g.notebook_default_kernel
  if type(kernel) == "string" and kernel ~= "" then
    return kernel
  end

  return "python3"
end

local function notebook_statusline_component()
  local ok, molten_status = pcall(require, "molten.status")
  if not ok then
    return ""
  end

  local kernels = molten_status.kernels()
  if not kernels or kernels == "" then
    return ""
  end

  return "  nb:" .. kernels .. " "
end

vim.o.statusline = table.concat({
  "%<",
  " %f",
  "%m%r",
  "%{v:lua.git_statusline_component()}",
  "%{v:lua.notebook_statusline_component()}",
  "%=",
  " %y",
  " %p%%",
  " %l:%c ",
})
_G.git_statusline_component = git_statusline_component
_G.notebook_statusline_component = notebook_statusline_component

-- Auto reload when files change outside nvim
vim.o.autoread = true
local external_file_sync = vim.api.nvim_create_augroup("external-file-sync", { clear = true })
local sidebar_refresh_timer = nil

local function refresh_sidebar_views()
  local ok, manager = pcall(require, "neo-tree.sources.manager")
  if not ok then
    return
  end

  pcall(manager.refresh, "filesystem")
  pcall(manager.refresh, "buffers")
  pcall(manager.refresh, "git_status")
end

local function schedule_sidebar_refresh()
  if sidebar_refresh_timer then
    sidebar_refresh_timer:stop()
    sidebar_refresh_timer:close()
  end

  sidebar_refresh_timer = vim.uv.new_timer()
  if not sidebar_refresh_timer then
    return
  end

  sidebar_refresh_timer:start(120, 0, vim.schedule_wrap(function()
    refresh_sidebar_views()
    if sidebar_refresh_timer then
      sidebar_refresh_timer:stop()
      sidebar_refresh_timer:close()
      sidebar_refresh_timer = nil
    end
  end))
end

vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "TermLeave" }, {
  group = external_file_sync,
  callback = function()
    if vim.fn.mode() == "c" then
      return
    end

    if vim.bo.buftype ~= "" then
      schedule_sidebar_refresh()
      return
    end

    vim.cmd("checktime")
    schedule_sidebar_refresh()
  end,
})

vim.api.nvim_create_autocmd({ "DirChanged", "ShellCmdPost", "VimResume" }, {
  group = external_file_sync,
  callback = function()
    schedule_sidebar_refresh()
  end,
})

vim.api.nvim_create_autocmd("FileChangedShellPost", {
  group = external_file_sync,
  callback = function()
    refresh_sidebar_views()

    vim.schedule(function()
      vim.notify("Reloaded file changed outside Neovim", vim.log.levels.INFO, { title = "File Sync" })
    end)
  end,
})

-- =========================================================
-- lazy.nvim bootstrap
-- =========================================================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- =========================================================
-- Plugins
-- =========================================================
require("lazy").setup({
  -- Theme
  {
    "navarasu/onedark.nvim",
    priority = 1000,
    config = function()
      require("onedark").setup({
        style = "dark",
        transparent = false,
        term_colors = true,
        code_style = {
          comments = "italic",
          keywords = "none",
          functions = "none",
          strings = "none",
          variables = "none",
        },
      })
      require("onedark").load()

      vim.api.nvim_set_hl(0, "NeoTreeGitModified", { fg = "#E5C07B", italic = false })
      vim.api.nvim_set_hl(0, "NeoTreeGitAdded", { fg = "#98C379", italic = false })
      vim.api.nvim_set_hl(0, "NeoTreeGitUntracked", { fg = "#ABB2BF", italic = false })
      vim.api.nvim_set_hl(0, "NeoTreeGitDeleted", { fg = "#E06C75", italic = false })
      vim.api.nvim_set_hl(0, "NeoTreeGitIgnored", { fg = "#5C6370", italic = false })

      vim.api.nvim_set_hl(0, "NeoTreeDotfile", { fg = "#5C6370", italic = false })
      vim.api.nvim_set_hl(0, "NeoTreeFileName", { fg = "#ABB2BF", italic = false })
      vim.api.nvim_set_hl(0, "NeoTreeDirectoryName", { fg = "#ABB2BF", italic = false })
      vim.api.nvim_set_hl(0, "NeoTreeDirectoryIcon", { fg = "#61AFEF", italic = false })
      vim.api.nvim_set_hl(0, "NeoTreeFileIcon", { fg = "#ABB2BF", italic = false })

      vim.api.nvim_set_hl(0, "WinSeparator", { fg = "#3A404A" })
      vim.api.nvim_set_hl(0, "VertSplit", { fg = "#3A404A" })

    end,
  },

  -- Outline of Codes
  {
    "stevearc/aerial.nvim",
    branch = "nvim-0.11",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      require("aerial").setup({
        layout = {
          default_direction = "right",
          min_width = 10,
        },
        attach_mode = "window",
        show_guides = true,
        filter_kind = false,
      })

      vim.keymap.set("n", "<leader>a", "<cmd>AerialToggle right<CR>", { silent = true })
    end,
  },

  -- Icons
  { "nvim-tree/nvim-web-devicons", lazy = true },

  -- File tree
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    config = function()
      local function lock_neotree_horizontal_scroll(win)
        if not win or not vim.api.nvim_win_is_valid(win) then
          return
        end

        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].filetype ~= "neo-tree" then
          return
        end

        vim.wo[win].wrap = false
        vim.wo[win].sidescrolloff = 0
        vim.wo[win].winfixwidth = false

        vim.api.nvim_win_call(win, function()
          local view = vim.fn.winsaveview()
          if view.leftcol ~= 0 or view.skipcol ~= 0 then
            view.leftcol = 0
            view.skipcol = 0
            vim.fn.winrestview(view)
          end
        end)
      end

      local function disable_neotree_horizontal_movement(buf)
        local opts = { buffer = buf, silent = true, noremap = true, nowait = true }
        local noops = {
          "zh",
          "zl",
          "zH",
          "zL",
          "zs",
          "ze",
          "<ScrollWheelLeft>",
          "<ScrollWheelRight>",
          "<S-ScrollWheelLeft>",
          "<S-ScrollWheelRight>",
        }

        for _, lhs in ipairs(noops) do
          vim.keymap.set("n", lhs, "<Nop>", opts)
        end
      end

      local function sync_neotree_to_dir(dir)
        if not dir or vim.fn.isdirectory(dir) == 0 then
          return
        end

        local current_win = vim.api.nvim_get_current_win()
        local ok, manager = pcall(require, "neo-tree.sources.manager")
        if ok then
          pcall(manager.navigate, "filesystem", dir, nil, nil, false)
        end

        if vim.api.nvim_win_is_valid(current_win) then
          pcall(vim.api.nvim_set_current_win, current_win)
        end
      end

      require("neo-tree").setup({
        close_if_last_window = false,
        popup_border_style = "rounded",
        window = {
          width = 24,
          auto_expand_width = false,
          mappings = {
            ["<space>"] = "toggle_node",
            ["<cr>"] = "open",
            ["<2-LeftMouse>"] = "open",
          },
        },
        filesystem = {
          bind_to_cwd = true,
          follow_current_file = { enabled = true },
          use_libuv_file_watcher = false,
          filtered_items = {
            hide_dotfiles = false,
            hide_gitignored = true,
          },
          group_empty_dirs = true,
        },
        default_component_configs = {
          git_status = {
            symbols = {
              added = "●",
              modified = "●",
              deleted = "✖",
              renamed = "➜",
              untracked = "○",
              ignored = "",
              unstaged = "●",
              staged = "●",
              conflict = "!",
            },
          },
        },
      })

      vim.api.nvim_create_autocmd("VimEnter", {
        callback = function()
          if vim.fn.argc() == 0 then
            vim.cmd("Neotree show")
            vim.schedule(ensure_terminal_sidebar_panel)
          end
        end,
      })

      local neotree_ui = vim.api.nvim_create_augroup("neotree-ui", { clear = true })

      vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter", "BufEnter", "WinEnter" }, {
        group = neotree_ui,
        callback = function(args)
          if vim.bo[args.buf].filetype ~= "neo-tree" then
            return
          end

          vim.cmd.stopinsert()
          vim.keymap.set("n", "i", "i", { buffer = args.buf, noremap = true, silent = true })
          disable_neotree_horizontal_movement(args.buf)
          lock_neotree_horizontal_scroll(vim.api.nvim_get_current_win())
          vim.schedule(ensure_terminal_sidebar_panel)
        end,
      })

      vim.api.nvim_create_autocmd("WinScrolled", {
        group = neotree_ui,
        callback = function()
          for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            lock_neotree_horizontal_scroll(win)
          end
        end,
      })

      vim.api.nvim_create_autocmd("TermRequest", {
        group = neotree_ui,
        desc = "Sync cwd and open files from terminal OSC",
        callback = function(ev)
          local seq = ev.data and ev.data.sequence or ""
          local open_prefix = "\x1b]51;open:"
          if seq:sub(1, #open_prefix) == open_prefix then
            local target = seq:gsub("^\x1b]51;open:file://[^/]*", ""):gsub("\x1b\\$", ""):gsub("\x07$", "")
            if target == "" then
              return
            end

            vim.schedule(function()
              if vim.fn.isdirectory(target) == 1 then
                vim.cmd.cd(vim.fn.fnameescape(target))
                vim.cmd("Neotree show")
                sync_neotree_to_dir(target)
              elseif vim.fn.filereadable(target) == 1 then
                open_path_in_edit_window(target)
              end
            end)
            return
          end

          if seq:sub(1, 4) ~= "\x1b]7;" then
            return
          end

          local dir = seq:gsub("\x1b]7;file://[^/]*", ""):gsub("\x1b\\$", ""):gsub("\x07$", "")
          if vim.fn.isdirectory(dir) == 0 then
            return
          end

          vim.api.nvim_buf_set_var(ev.buf, "osc7_dir", dir)
          vim.cmd.cd(vim.fn.fnameescape(dir))
          sync_neotree_to_dir(dir)
        end,
      })

      vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
        group = neotree_ui,
        callback = function()
          local ok, dir = pcall(vim.api.nvim_buf_get_var, 0, "osc7_dir")
          if ok and vim.fn.isdirectory(dir) == 1 then
            vim.cmd.cd(vim.fn.fnameescape(dir))
            sync_neotree_to_dir(dir)
          end
        end,
      })

      local function install_terminal_cwd_reporting(buf)
        if vim.bo[buf].buftype ~= "terminal" then
          return
        end

        if vim.b[buf].osc7_installed then
          return
        end

        local job = vim.b[buf].terminal_job_id
        if not job then
          return
        end

        local shell = vim.o.shell or ""
        if not shell:match("zsh$") then
          return
        end

        vim.b[buf].osc7_installed = true
        vim.defer_fn(function()
          if not vim.api.nvim_buf_is_valid(buf) then
            return
          end

          local hooks_path = vim.fn.stdpath("config") .. "/terminal-hooks.zsh"
          local source_cmd = string.format("source %s >/dev/null 2>&1\nclear\n", vim.fn.fnameescape(hooks_path))
          pcall(vim.fn.chansend, job, source_cmd)
        end, 100)
      end

      vim.api.nvim_create_autocmd("TermOpen", {
        group = neotree_ui,
        callback = function(args)
          install_terminal_cwd_reporting(args.buf)
        end,
      })

      vim.api.nvim_create_autocmd("VimEnter", {
        callback = function()
          vim.defer_fn(function()
            ensure_edit_window()
            open_named_terminal(1, "Terminal 1")
          end, 100)
        end,
      })
    end,
  },

  -- Bottom terminal + Aider terminal
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    lazy = false,
    config = function()
      require("toggleterm").setup({
        open_mapping = nil,
        direction = "horizontal",
        size = 15,
        autochdir = true,
        persist_mode = false,
        winbar = { enabled = false },
      })

      local Terminal = require("toggleterm.terminal").Terminal

      local aider = Terminal:new({
        cmd = "aider --model ollama_chat/qwen2.5-coder:14b",
        count = 99,
        direction = "horizontal",
        size = 15,
        hidden = true,
        close_on_exit = false,
        display_name = "Aider",
      })

      vim.keymap.set("n", "<leader>aa", function()
        aider:toggle()
      end, { noremap = true, silent = true, desc = "Toggle Aider" })

      local terminal_sidebar_ui = vim.api.nvim_create_augroup("terminal-sidebar-ui", { clear = true })

      vim.api.nvim_create_autocmd({ "TermOpen", "TermClose", "BufEnter", "WinEnter" }, {
        group = terminal_sidebar_ui,
        callback = function()
          vim.schedule(function()
            ensure_terminal_sidebar_panel()
            render_terminal_sidebar()
          end)
        end,
      })
    end,
  },

  -- Open ipynb files as readable percent-format notebooks
  {
    "GCBallesteros/jupytext.nvim",
    lazy = false,
    config = function()
      require("jupytext").setup({
        style = "percent",
        output_extension = "auto",
        custom_language_formatting = {
          python = {
            extension = "py",
            style = "percent",
            force_ft = "python",
          },
        },
      })
    end,
  },

  -- Jupyter kernel execution and output
  {
    "benlubas/molten-nvim",
    build = ":UpdateRemotePlugins",
    lazy = false,
    init = function()
      vim.g.notebook_default_kernel = "python3"
      vim.g.molten_auto_init_behavior = "init"
      vim.g.molten_image_provider = "none"
      vim.g.molten_output_virt_lines = true
      vim.g.molten_virt_text_output = true
      vim.g.molten_virt_text_max_lines = 12
      vim.g.molten_wrap_output = true
      vim.g.molten_output_show_exec_time = true
      vim.g.molten_tick_rate = 200
      vim.g.molten_limit_output_chars = 200000
    end,
    config = function()
      vim.api.nvim_create_user_command("NotebookInit", function(opts)
        local kernel = opts.args ~= "" and opts.args or notebook_default_kernel()
        vim.cmd("MoltenInit " .. vim.fn.fnameescape(kernel))
      end, {
        nargs = "?",
        desc = "Initialize Molten with the default or provided kernel",
      })

      vim.api.nvim_create_user_command("NotebookInitSelect", function()
        vim.cmd("MoltenInit")
      end, {
        desc = "Pick a kernel and initialize Molten",
      })

      vim.api.nvim_create_user_command("NotebookSaveOutputs", function()
        local path = vim.api.nvim_buf_get_name(0)
        if path == "" then
          vim.notify("Current buffer has no file path", vim.log.levels.WARN, { title = "Notebook" })
          return
        end

        vim.cmd("MoltenExportOutput! " .. vim.fn.fnameescape(path))
      end, {
        desc = "Export current Molten outputs back to the notebook file",
      })
    end,
  },

  -- Move and run notebook cells with VS Code-like markers
  {
    "GCBallesteros/NotebookNavigator.nvim",
    ft = { "python", "markdown", "quarto" },
    config = function()
      require("notebook-navigator").setup({
        repl_provider = "molten",
        syntax_highlight = true,
      })
    end,
  },

  -- Fuzzy finder
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("telescope").setup({})
    end,
  },

  -- Git signs in the gutter + hunk actions
  {
    "lewis6991/gitsigns.nvim",
    config = function()
      require("gitsigns").setup({
        current_line_blame = false,
        signs_staged_enable = true,
      })
    end,
  },

  -- Git porcelain inside Neovim
  { "tpope/vim-fugitive" },

  -- Buffer tabs
  {
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("bufferline").setup({
        options = {
          diagnostics = "nvim_lsp",
          always_show_bufferline = true,
          numbers = "ordinal",
          left_mouse_command = function(bufnr)
            vim.schedule(function()
              if vim.bo[bufnr].filetype == "toggleterm" or vim.bo[bufnr].buftype == "terminal" then
                focus_toggleterm_buffer(bufnr)
                return
              end

              open_buffer_in_edit_window(bufnr)
            end)
          end,
          close_command = function(bufnr)
            local term = find_toggleterm_by_buf(bufnr)
            if term then
              term:shutdown()
              return
            end

            smart_bdelete(bufnr)
          end,
          right_mouse_command = function(bufnr)
            local term = find_toggleterm_by_buf(bufnr)
            if term then
              term:shutdown()
              return
            end

            smart_bdelete(bufnr)
          end,
          name_formatter = function(buf)
            if vim.bo[buf.bufnr].filetype ~= "toggleterm" and vim.bo[buf.bufnr].buftype ~= "terminal" then
              return nil
            end

            local term = find_toggleterm_by_buf(buf.bufnr)
            if not term then
              return "Terminal"
            end

            return "Terminal " .. term.id
          end,
          offsets = {
            {
              filetype = "neo-tree",
              text = "Explorer",
              text_align = "center",
              separator = true,
            },
          },
          custom_filter = function(buf_number)
            local bufname = vim.api.nvim_buf_get_name(buf_number)
            local buftype = vim.bo[buf_number].buftype

            if buftype == "terminal" or vim.bo[buf_number].filetype == "toggleterm" then
              return false
            end

            if string.match(bufname, "term://") then
              return false
            end

            return true
          end,
        },
      })
    end,
  },

  -- LSP installer + configs
  { "neovim/nvim-lspconfig" },
  {
    "williamboman/mason.nvim",
    config = function()
      require("mason").setup({})
    end,
  },
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = {
      "williamboman/mason.nvim",
      "neovim/nvim-lspconfig",
    },
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = { "lua_ls", "pyright", "ts_ls" },
      })
    end,
  },

  -- Completion
  { "L3MON4D3/LuaSnip", version = "v2.*", build = "make install_jsregexp" },
  { "saadparwaiz1/cmp_luasnip" },
  { "hrsh7th/cmp-buffer" },
  { "hrsh7th/cmp-cmdline" },
  { "hrsh7th/cmp-path" },
  { "hrsh7th/cmp-nvim-lsp" },
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-cmdline",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "path" },
          { name = "buffer" },
          { name = "luasnip" },
        }),
      })

      cmp.setup.cmdline(":", {
        mapping = cmp.mapping.preset.cmdline(),
        sources = cmp.config.sources({
          { name = "path" },
        }, {
          {
            name = "cmdline",
            option = {
              ignore_cmds = { "Man", "!" },
            },
          },
        }),
      })
    end,
  },
})

-- =========================================================
-- Keymaps
-- =========================================================
local map = vim.keymap.set
local opts = { noremap = true, silent = true }

-- Explorer
map("n", "<leader>e", "<cmd>Neotree toggle<CR>", opts)
map("n", "<leader>o", "<cmd>Neotree focus<CR>", opts)
map("n", "<leader>1", focus_sidebar, opts)
map("n", "<leader>2", focus_code_panel, opts)
map("n", "<leader>3", focus_terminal_panel, opts)
map("n", "<leader>4", focus_terminal_list_panel, opts)
map("n", "<F1>", focus_sidebar, opts)
map("n", "<F2>", focus_code_panel, opts)
map("n", "<F3>", focus_terminal_panel, opts)
map("n", "<F4>", focus_terminal_list_panel, opts)
map("n", "<F5>", restart_nvim_in_place, opts)
map("n", "<F6>", cycle_main_panes, opts)
map("n", "<S-F6>", cycle_main_panes_reverse, opts)
map("n", "<F7>", restart_nvim_in_place, opts)
map("n", "<F8>", cycle_main_panes, opts)
map("n", "<S-F8>", cycle_main_panes_reverse, opts)
map("n", "<leader><tab>", cycle_main_panes, opts)
map("n", "<leader><S-Tab>", cycle_main_panes_reverse, opts)
map("n", "<C-h>", focus_sidebar, opts)
map("n", "<C-l>", focus_code_panel, opts)
map("n", "<C-j>", focus_terminal_panel, opts)
map("n", "<C-k>", focus_terminal_list_panel, opts)
map("n", "<C-;>", cycle_main_panes, opts)
map("n", "<C-:>", cycle_main_panes_reverse, opts)

-- Terminal
map("n", "<leader>t", toggle_primary_terminal, opts)
map("n", "<leader>tn", open_new_terminal, opts)
map("n", "<leader>tt", open_new_terminal, opts)
map("n", "<leader>ts", "<cmd>TermSelect<CR>", opts)
map("n", "<leader>tj", function()
  cycle_toggleterm(1)
end, opts)
map("n", "<leader>tk", function()
  cycle_toggleterm(-1)
end, opts)
map("n", "<leader>tx", close_current_terminal, opts)
map({ "n", "t" }, "<C-\\>", toggle_primary_terminal, opts)
for i = 1, 9 do
  map("n", "<leader>t" .. i, function()
    open_terminal_slot(i)
  end, opts)
end

-- Notebook
map("n", "<leader>ni", "<cmd>NotebookInit<CR>", opts)
map("n", "<leader>nI", "<cmd>NotebookInitSelect<CR>", opts)
map("n", "<leader>ns", "<cmd>NotebookSaveOutputs<CR>", opts)
map("n", "<leader>nr", function()
  require("notebook-navigator").run_cell()
end, opts)
map("n", "<leader>nn", function()
  require("notebook-navigator").run_and_move()
end, opts)
map("n", "<leader>nj", function()
  require("notebook-navigator").move_cell("d")
end, opts)
map("n", "<leader>nk", function()
  require("notebook-navigator").move_cell("u")
end, opts)
map("n", "<leader>no", "<cmd>noautocmd MoltenEnterOutput<CR>", opts)
map("n", "<leader>nh", "<cmd>MoltenHideOutput<CR>", opts)
map("n", "<leader>nx", "<cmd>MoltenInterrupt<CR>", opts)
map("n", "<leader>nR", "<cmd>MoltenRestart!<CR>", opts)

-- Telescope
map("n", "<leader>ff", "<cmd>Telescope find_files<CR>", opts)
map("n", "<leader>fg", "<cmd>Telescope live_grep<CR>", opts)
map("n", "<leader>fb", "<cmd>Telescope buffers<CR>", opts)
map("n", "<leader>fh", "<cmd>Telescope help_tags<CR>", opts)

-- Git
map("n", "<leader>gs", "<cmd>Git<CR>", opts)
map("n", "<leader>gb", "<cmd>Git blame<CR>", opts)
map("n", "<leader>gD", "<cmd>Gvdiffsplit<CR>", opts)
map("n", "]h", function()
  require("gitsigns").nav_hunk("next")
end, opts)
map("n", "[h", function()
  require("gitsigns").nav_hunk("prev")
end, opts)
map("n", "<leader>gp", function()
  require("gitsigns").preview_hunk_inline()
end, opts)
map("n", "<leader>gr", function()
  require("gitsigns").reset_hunk()
end, opts)
map("n", "<leader>gS", function()
  require("gitsigns").stage_hunk()
end, opts)
map("n", "<leader>gu", function()
  require("gitsigns").undo_stage_hunk()
end, opts)
map("n", "<leader>gB", function()
  require("gitsigns").blame_line({ full = true })
end, opts)

-- Buffers
map("n", "<leader>bn", "<cmd>BufferLineCycleNext<CR>", opts)
map("n", "<leader>bp", "<cmd>BufferLineCyclePrev<CR>", opts)
map("n", "<leader>bd", function()
  smart_bdelete()
end, opts)

-- Save/quit
map("n", "<leader>w", "<cmd>w<CR>", opts)
map("n", "<leader>q", "<cmd>q<CR>", opts)
map("n", "<leader>R", restart_nvim_in_place, opts)

-- macOS-style shortcuts
map("n", "<D-c>", '"+yy', opts)
map("v", "<D-c>", '"+y', opts)

map("n", "<D-v>", '"+P', opts)
map("v", "<D-v>", '"+P', opts)
map("i", "<D-v>", "<C-r>+", { noremap = true })
map("c", "<D-v>", "<C-r>+", { noremap = true })
map("t", "<D-v>", [[<C-\><C-n>"+pa]], { noremap = true, silent = true })

map({ "n", "v" }, "<D-s>", "<cmd>w<CR>", opts)
map("i", "<D-s>", "<C-o><cmd>w<CR>", { noremap = true, silent = true })
map("t", "<D-s>", [[<C-\><C-n><cmd>w<CR>i]], { noremap = true, silent = true })

map({ "n", "i", "v" }, "<D-t>", "<cmd>enew<CR>", opts)
map("t", "<D-t>", [[<C-\><C-n><cmd>enew<CR>]], { noremap = true, silent = true })

map({ "n", "i", "v" }, "<D-n>", "<cmd>enew<CR>", opts)
map("t", "<D-n>", [[<C-\><C-n><cmd>enew<CR>]], { noremap = true, silent = true })

map("n", "<D-1>", focus_sidebar, opts)
map("n", "<D-2>", focus_code_panel, opts)
map("n", "<D-3>", focus_terminal_panel, opts)
map("n", "<D-4>", focus_terminal_list_panel, opts)
map("n", "<D-r>", restart_nvim_in_place, opts)
map("n", "<D-]>", cycle_main_panes, opts)
map("n", "<D-[>", cycle_main_panes_reverse, opts)
map("n", "<C-Tab>", cycle_main_panes, opts)
map("n", "<C-S-Tab>", cycle_main_panes_reverse, opts)
map("n", "<C-PageDown>", cycle_main_panes, opts)
map("n", "<C-PageUp>", cycle_main_panes_reverse, opts)
map("n", "<A-Tab>", cycle_main_panes, opts)
map("n", "<A-S-Tab>", cycle_main_panes_reverse, opts)
map("i", "<D-1>", function()
  vim.cmd("stopinsert")
  focus_sidebar()
end, opts)
map("i", "<F1>", function()
  vim.cmd("stopinsert")
  focus_sidebar()
end, opts)
map("i", "<D-2>", function()
  vim.cmd("stopinsert")
  focus_code_panel()
end, opts)
map("i", "<F2>", function()
  vim.cmd("stopinsert")
  focus_code_panel()
end, opts)
map("i", "<D-3>", function()
  vim.cmd("stopinsert")
  focus_terminal_panel()
end, opts)
map("i", "<F3>", function()
  vim.cmd("stopinsert")
  focus_terminal_panel()
end, opts)
map("i", "<D-4>", function()
  vim.cmd("stopinsert")
  focus_terminal_list_panel()
end, opts)
map("i", "<F4>", function()
  vim.cmd("stopinsert")
  focus_terminal_list_panel()
end, opts)
map("i", "<D-r>", function()
  vim.cmd("stopinsert")
  restart_nvim_in_place()
end, opts)
map("i", "<F5>", function()
  vim.cmd("stopinsert")
  restart_nvim_in_place()
end, opts)
map("i", "<F6>", function()
  vim.cmd("stopinsert")
  cycle_main_panes()
end, opts)
map("i", "<S-F6>", function()
  vim.cmd("stopinsert")
  cycle_main_panes_reverse()
end, opts)
map("i", "<F7>", function()
  vim.cmd("stopinsert")
  restart_nvim_in_place()
end, opts)
map("i", "<F8>", function()
  vim.cmd("stopinsert")
  cycle_main_panes()
end, opts)
map("i", "<S-F8>", function()
  vim.cmd("stopinsert")
  cycle_main_panes_reverse()
end, opts)
map("i", "<D-]>", function()
  vim.cmd("stopinsert")
  cycle_main_panes()
end, opts)
map("i", "<D-[>", function()
  vim.cmd("stopinsert")
  cycle_main_panes_reverse()
end, opts)
map("i", "<C-Tab>", function()
  vim.cmd("stopinsert")
  cycle_main_panes()
end, opts)
map("i", "<C-S-Tab>", function()
  vim.cmd("stopinsert")
  cycle_main_panes_reverse()
end, opts)
map("i", "<C-PageDown>", function()
  vim.cmd("stopinsert")
  cycle_main_panes()
end, opts)
map("i", "<C-PageUp>", function()
  vim.cmd("stopinsert")
  cycle_main_panes_reverse()
end, opts)
map("i", "<A-Tab>", function()
  vim.cmd("stopinsert")
  cycle_main_panes()
end, opts)
map("i", "<A-S-Tab>", function()
  vim.cmd("stopinsert")
  cycle_main_panes_reverse()
end, opts)
map("i", "<C-h>", function()
  vim.cmd("stopinsert")
  focus_sidebar()
end, opts)
map("i", "<C-l>", function()
  vim.cmd("stopinsert")
  focus_code_panel()
end, opts)
map("i", "<C-j>", function()
  vim.cmd("stopinsert")
  focus_terminal_panel()
end, opts)
map("i", "<C-k>", function()
  vim.cmd("stopinsert")
  focus_terminal_list_panel()
end, opts)
map("i", "<C-;>", function()
  vim.cmd("stopinsert")
  cycle_main_panes()
end, opts)
map("i", "<C-:>", function()
  vim.cmd("stopinsert")
  cycle_main_panes_reverse()
end, opts)
map("t", "<D-1>", function()
  leave_terminal_and(focus_sidebar)
end, opts)
map("t", "<F1>", function()
  leave_terminal_and(focus_sidebar)
end, opts)
map("t", "<D-2>", function()
  leave_terminal_and(focus_code_panel)
end, opts)
map("t", "<F2>", function()
  leave_terminal_and(focus_code_panel)
end, opts)
map("t", "<D-3>", function()
  leave_terminal_and(focus_terminal_panel)
end, opts)
map("t", "<F3>", function()
  leave_terminal_and(focus_terminal_panel)
end, opts)
map("t", "<D-4>", function()
  leave_terminal_and(focus_terminal_list_panel)
end, opts)
map("t", "<F4>", function()
  leave_terminal_and(focus_terminal_list_panel)
end, opts)
map("t", "<D-r>", function()
  leave_terminal_and(restart_nvim_in_place)
end, opts)
map("t", "<F5>", function()
  leave_terminal_and(restart_nvim_in_place)
end, opts)
map("t", "<F6>", function()
  leave_terminal_and(cycle_main_panes)
end, opts)
map("t", "<S-F6>", function()
  leave_terminal_and(cycle_main_panes_reverse)
end, opts)
map("t", "<F7>", function()
  leave_terminal_and(restart_nvim_in_place)
end, opts)
map("t", "<F8>", function()
  leave_terminal_and(cycle_main_panes)
end, opts)
map("t", "<S-F8>", function()
  leave_terminal_and(cycle_main_panes_reverse)
end, opts)
map("t", "<D-]>", function()
  leave_terminal_and(cycle_main_panes)
end, opts)
map("t", "<D-[>", function()
  leave_terminal_and(cycle_main_panes_reverse)
end, opts)
map("t", "<C-Tab>", function()
  leave_terminal_and(cycle_main_panes)
end, opts)
map("t", "<C-S-Tab>", function()
  leave_terminal_and(cycle_main_panes_reverse)
end, opts)
map("t", "<C-PageDown>", function()
  leave_terminal_and(cycle_main_panes)
end, opts)
map("t", "<C-PageUp>", function()
  leave_terminal_and(cycle_main_panes_reverse)
end, opts)
map("t", "<A-Tab>", function()
  leave_terminal_and(cycle_main_panes)
end, opts)
map("t", "<A-S-Tab>", function()
  leave_terminal_and(cycle_main_panes_reverse)
end, opts)
map("t", "<C-h>", function()
  leave_terminal_and(focus_sidebar)
end, opts)
map("t", "<C-l>", function()
  leave_terminal_and(focus_code_panel)
end, opts)
map("t", "<C-j>", function()
  leave_terminal_and(focus_terminal_panel)
end, opts)
map("t", "<C-k>", function()
  leave_terminal_and(focus_terminal_list_panel)
end, opts)
map("t", "<C-;>", function()
  leave_terminal_and(cycle_main_panes)
end, opts)
map("t", "<C-:>", function()
  leave_terminal_and(cycle_main_panes_reverse)
end, opts)

vim.api.nvim_create_autocmd("TermOpen", {
  callback = function(args)
    vim.b[args.buf].clear_on_first_enter = true
    vim.cmd("startinsert")
  end,
})

vim.api.nvim_create_autocmd("TermEnter", {
  callback = function(args)
    if not vim.b[args.buf].clear_on_first_enter then
      vim.cmd("startinsert")
      return
    end

    vim.b[args.buf].clear_on_first_enter = false

    vim.defer_fn(function()
      if not vim.api.nvim_buf_is_valid(args.buf) then
        return
      end

      local job = vim.b[args.buf].terminal_job_id
      if job then
        pcall(vim.fn.chansend, job, "clear\n")
      end
    end, 180)

    vim.cmd("startinsert")
  end,
})

vim.api.nvim_create_autocmd("BufEnter", {
  pattern = "term://*",
  callback = function()
    vim.cmd("startinsert")
  end,
})

vim.api.nvim_create_autocmd("ModeChanged", {
  callback = function()
    if suppress_terminal_reentry then
      return
    end

    if vim.bo.buftype ~= "terminal" then
      return
    end

    if vim.api.nvim_get_mode().mode ~= "t" then
      vim.schedule(function()
        if vim.bo.buftype == "terminal" then
          vim.cmd("startinsert")
        end
      end)
    end
  end,
})

vim.api.nvim_create_autocmd("InsertEnter", {
  callback = function()
    if vim.bo.filetype ~= "neo-tree" then
      return
    end

    vim.schedule(begin_neotree_rename)
  end,
})

vim.api.nvim_create_user_command("RestartNvimHere", restart_nvim_in_place, {
  desc = "Restart Neovim and restore the current session in the same cwd",
})

-- =========================================================
-- Diagnostics + LSP keymaps
-- =========================================================
vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
})

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local bufnr = args.buf
    local client_id = args.data and args.data.client_id

    if vim.b[bufnr].large_file and client_id then
      vim.schedule(function()
        pcall(vim.lsp.buf_detach_client, bufnr, client_id)
      end)
      return
    end

    local function bufmap(mode, lhs, rhs)
      vim.keymap.set(mode, lhs, rhs, {
        buffer = bufnr,
        silent = true,
        noremap = true,
      })
    end

    bufmap("n", "gd", vim.lsp.buf.definition)
    bufmap("n", "gr", vim.lsp.buf.references)
    bufmap("n", "K", vim.lsp.buf.hover)
    bufmap("n", "<leader>rn", vim.lsp.buf.rename)
    bufmap("n", "<leader>ca", vim.lsp.buf.code_action)
    bufmap("n", "<leader>ds", vim.diagnostic.open_float)
    bufmap("n", "[d", vim.diagnostic.goto_prev)
    bufmap("n", "]d", vim.diagnostic.goto_next)
  end,
})

-- =========================================================
-- LSP setup for Neovim 0.11+
-- =========================================================
local capabilities = require("cmp_nvim_lsp").default_capabilities()

vim.lsp.config("lua_ls", {
  capabilities = capabilities,
  settings = {
    Lua = {
      diagnostics = { globals = { "vim" } },
      workspace = { checkThirdParty = false },
      telemetry = { enable = false },
    },
  },
})

vim.lsp.config("pyright", {
  capabilities = capabilities,
})

vim.lsp.config("ts_ls", {
  capabilities = capabilities,
})

vim.lsp.enable({ "lua_ls", "pyright", "ts_ls" })
