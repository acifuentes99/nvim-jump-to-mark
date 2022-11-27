local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local make_entry = require "fzf-lua.make_entry"

local M = {}

-- will hold current/previous buffer/tab
local __STATE = {}

local UPDATE_STATE = function()
  __STATE = {
    curtabidx = vim.fn.tabpagenr(),
    curtab = vim.api.nvim_win_get_tabpage(0),
    curbuf = vim.api.nvim_get_current_buf(),
    prevbuf = vim.fn.bufnr("#"),
    buflist = vim.api.nvim_list_bufs(),
    bufmap = (function()
      local map = {}
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        map[b] = true
      end
      return map
    end)()
  }
end

-- OWN FUNCTIONS TO FILTER QUICKFIX LIST
function qf_list_by_buffer(qf_list)
  local dict = {}
  for _, x in pairs(qf_list) do
    if not dict[x.bufnr] then
      local new_table = {}
      table.insert(new_table, x)
      dict[x.bufnr] = new_table
    else
      table.insert(dict[x.bufnr], x)
    end
  end
  return dict
end

function qf_by_tab(locations, tab_to_buf)
  local result = qf_list_by_buffer(locations)
  local qf_by_tab = {}
  local added_buffers = {}
  local count = 0
  for tabnr, bufs_on_tab in ipairs(tab_to_buf) do
    qf_by_tab[tabnr] = {}
    for bufnr, _ in pairs(bufs_on_tab) do
      if (not added_buffers[bufnr]) then
        if not qf_by_tab[tabnr][result[bufnr]] then
          if result[bufnr] then
            qf_by_tab[tabnr][bufnr] = result[bufnr]
          end
        else
          table.insert(qf_by_tab[tabnr][result[bufnr].bufnr], result[bufnr])
        end
        added_buffers[bufnr] = true
      end

    end
  end
  return qf_by_tab
end

function jump_to_win_line(desiredbuf, line)
  local alltabpages = vim.api.nvim_list_tabpages();
  local buffound = false
  for _,tabpage in ipairs(alltabpages) do
      local winlist = vim.api.nvim_tabpage_list_wins(tabpage)
      -- for each window, check its bufer
      for _,win in ipairs(winlist) do
          local buf = vim.api.nvim_win_get_buf(win)
          -- move to it if it's what you want
          if (buf == desiredbuf) then
              buffound = true
              vim.api.nvim_win_set_cursor(win, {line, 0})
              vim.api.nvim_set_current_win(win)
              vim.api.nvim_input('zz')
              break
          end
      end
      if (buffound) then
          break
      end
  end

  -- open it in current window if it's not in any window already
  if (not buffound) then
      vim.api.nvim_win_set_buf(0,desiredbuf)
  end
end


-- IMPORTING FROM BUFFERS/TABS
local filter_buffers = function(opts, unfiltered)
  if type(unfiltered) == "function" then
    unfiltered = unfiltered()
  end

  local curtab_bufnrs = {}
  if opts.current_tab_only then
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(__STATE.curtab)) do
      local b = vim.api.nvim_win_get_buf(w)
      curtab_bufnrs[b] = true
    end
  end

  local excluded = {}
  local bufnrs = vim.tbl_filter(function(b)
    if not opts.show_unlisted and 1 ~= vim.fn.buflisted(b) then
      excluded[b] = true
    end
    -- only hide unloaded buffers if opts.show_all_buffers is false, keep them listed if true or nil
    if opts.show_all_buffers == false and not vim.api.nvim_buf_is_loaded(b) then
      excluded[b] = true
    end
    if utils.buf_is_qf(b) then
      if opts.show_quickfix then
        -- show_quickfix trumps show_unlisted
        excluded[b] = nil
      else
        excluded[b] = true
      end
    end
    if opts.ignore_current_buffer and b == __STATE.curbuf then
      excluded[b] = true
    end
    if opts.current_tab_only and not curtab_bufnrs[b] then
      excluded[b] = true
    end
    if opts.no_term_buffers and utils.is_term_buffer(b) then
      excluded[b] = true
    end
    if opts.cwd_only and not path.is_relative(vim.api.nvim_buf_get_name(b), vim.loop.cwd()) then
      excluded[b] = true
    end
    return not excluded[b]
  end, unfiltered)

  return bufnrs, excluded
end

local populate_buffer_entries = function(opts, bufnrs, tabnr)
  local buffers = {}
  for _, bufnr in ipairs(bufnrs) do
    local flag = (bufnr == __STATE.curbuf and "%") or
        (bufnr == __STATE.prevbuf and "#") or " "

    local element = {
      bufnr = bufnr,
      flag = flag,
      info = vim.fn.getbufinfo(bufnr)[1],
    }

    -- get the correct lnum for tabbed buffers
    if tabnr then
      local winid = utils.winid_from_tab_buf(tabnr, bufnr)
      if winid then
        element.info.lnum = vim.api.nvim_win_get_cursor(winid)[1]
      end
    end

    table.insert(buffers, element)
  end
  if opts.sort_lastused then
    table.sort(buffers, function(a, b)
      return a.info.lastused > b.info.lastused
    end)
  end
  return buffers
end


local function gen_buffer_entry(opts, buf, hl_curbuf)
  -- local hidden = buf.info.hidden == 1 and 'h' or 'a'
  local hidden = ""
  local readonly = vim.api.nvim_buf_get_option(buf.bufnr, "readonly") and "=" or " "
  local changed = buf.info.changed == 1 and "+" or " "
  local flags = hidden .. readonly .. changed
  local leftbr = utils.ansi_codes.clear("[")
  local rightbr = utils.ansi_codes.clear("]")
  local bufname = #buf.info.name > 0 and
      path.relative(buf.info.name, vim.loop.cwd()) or
      utils.nvim_buf_get_name(buf.bufnr, buf.info)
  if opts.filename_only then
    bufname = path.basename(bufname)
  end
  -- replace $HOME with '~' for paths outside of cwd
  bufname = path.HOME_to_tilde(bufname)
  -- add line number
  bufname = ("%s:%s"):format(bufname, buf.info.lnum > 0 and buf.info.lnum or "")
  if buf.flag == "%" then
    flags = utils.ansi_codes.red(buf.flag) .. flags
    if hl_curbuf then
      -- no header line, highlight current buffer
      leftbr = utils.ansi_codes.green("[")
      rightbr = utils.ansi_codes.green("]")
      bufname = utils.ansi_codes.green(bufname)
    end
  elseif buf.flag == "#" then
    flags = utils.ansi_codes.cyan(buf.flag) .. flags
  else
    flags = utils.nbsp .. flags
  end
  local bufnrstr = string.format("%s%s%s", leftbr,
    utils.ansi_codes.yellow(string.format(buf.bufnr)), rightbr)
  local buficon = ""
  local hl = ""
  if opts.file_icons then
    if utils.is_term_bufname(buf.info.name) then
      -- get shell-like icon for terminal buffers
      buficon, hl = make_entry.get_devicon(buf.info.name, "sh")
    else
      local filename = path.tail(buf.info.name)
      local extension = path.extension(filename)
      buficon, hl = make_entry.get_devicon(filename, extension)
    end
    if opts.color_icons then
      buficon = utils.ansi_codes[hl](buficon)
    end
  end
  local item_str = string.format("%s%s%s%s%s%s%s%s",
    utils._if(opts._prefix, opts._prefix, ""),
    string.format("%-32s", bufnrstr),
    utils.nbsp,
    flags,
    utils.nbsp,
    buficon,
    utils.nbsp,
    bufname)
  return item_str
end

M.tabs = function(opts)
  local locations = vim.fn.getqflist()
  if vim.tbl_isempty(locations) then
    utils.info("Quickfix list is empty.")
    return
  end

  opts = config.normalize_opts(opts, config.globals.tabs)
  if not opts then return end

  opts.fn_pre_fzf = UPDATE_STATE

  opts._list_bufs = function()
    local res = {}
    for i, t in ipairs(vim.api.nvim_list_tabpages()) do
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(t)) do
        local b = vim.api.nvim_win_get_buf(w)
        -- since this function is called after fzf window
        -- is created, exclude the scratch fzf buffers
        if __STATE.bufmap[b] then
          opts._tab_to_buf[i] = opts._tab_to_buf[i] or {}
          opts._tab_to_buf[i][b] = t
          table.insert(res, b)
        end
      end
    end
    return res
  end

  local contents = function(cb)
    opts._tab_to_buf = {}

    local filtered, excluded = filter_buffers(opts, opts._list_bufs)
    if not next(filtered) then return end

    -- remove the filtered-out buffers
    for b, _ in pairs(excluded) do
      for _, bufnrs in pairs(opts._tab_to_buf) do
        bufnrs[b] = nil
      end
    end

    local qf_by_tab_ = qf_by_tab(locations, opts._tab_to_buf)

    for t, bufnrs in pairs(qf_by_tab_) do
      cb(("%d)%s%s\t%s"):format(t, utils.nbsp,
        utils.ansi_codes.blue("%s%s#%d"):format(opts.tab_title, utils.nbsp, t),
        (t == __STATE.curtabidx) and
        utils.ansi_codes.blue(utils.ansi_codes.bold(opts.tab_marker)) or ""))
      for bufnr, bufobj in pairs(bufnrs) do
            bufinfo = vim.fn.getbufinfo(bufnr)[1]
        for _, qtinfo in pairs(bufobj) do
          cb(_ .. ')   \27[0m[\27[0m\27[0;33m' .. bufinfo.bufnr .. '\27[0m\27[0m]\27[0m ' ..  qtinfo.text ..'  \27[0;31m%\27[0m   \27[38;2;81;160;207m\27[0m ' .. ' ' .. bufinfo.name .. ':' .. qtinfo.lnum )
        end
      end
    end
    cb(nil)
  end

  opts = core.set_fzf_field_index(opts, 3, "{}")

  opts.actions.default = function(selected)
    a, b = string.find(selected[1], "%[%d+")
    buffer = tonumber(string.sub(selected[1], a+1, b))
    c, d = string.find(selected[1], ":%d+")
    line = tonumber(string.sub(selected[1], c+1, d))
    jump_to_win_line(buffer, line)
  end

  core.fzf_exec(contents, opts)
end

M.tabs()
return M
