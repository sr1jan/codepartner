local M = {}

M.config = {
  api_key = nil,
  server_url = "http://localhost:5001",
  auto_start_server = true
}

M.explanation_win = nil
M.explanation_buf = nil
M.conversation_id = nil
M.conversation_history = {}

function M.get_plugin_dir()
  local p_dir =  vim.fn.fnamemodify(vim.api.nvim_get_runtime_file("lua/codepartner/init.lua", false)[1], ":h:h:h")
  return p_dir
end

function M.is_server_running()
  local pid_file = M.get_plugin_dir() .. "/server/codepartner_server.pid"
  if vim.fn.filereadable(pid_file) == 0 then
    return false
  end
  local pid = vim.fn.readfile(pid_file)[1]
  -- Check if the process is running
  local check_cmd = string.format("ps -p %s > /dev/null 2>&1", pid)
  local exit_code = os.execute(check_cmd)
  return exit_code == 0
end

function M.check_python_requirements()
  local plugin_dir = M.get_plugin_dir()
  local check_script = plugin_dir .. "/server/check_requirements.py"
  local cmd = string.format("python %s", check_script)
  local output = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    local missing_packages = output:match("Missing packages: (.+)")
    if missing_packages then
      local install = vim.fn.confirm("[CodePartner.nvim] The following Python packages are missing: " .. missing_packages .. "\nDo you want to install them?", "&Yes\n&No", 1)
      if install == 1 then
        local install_cmd = string.format("python -m pip install %s", missing_packages:gsub(", ", " "))
        print("install_cm", install_cmd)
        vim.fn.system(install_cmd)
        print("Packages installed successfully.")
      else
        print("Package installation skipped. The server may not function correctly.")
      end
    else
      print("Failed to check Python requirements.")
    end
  end
end

function M.start_server()
  if M.is_server_running() then
    print("CodePartner server is already running.")
    return
  end

  if not M.config.api_key then
    vim.api.nvim_err_writeln("CodePartner: API key is not set. Please configure it using require('codepartner').setup({api_key = 'your_api_key'})")
    return
  end

  M.check_python_requirements()

  local plugin_dir = M.get_plugin_dir()
  local server_script = plugin_dir .. "/server/start_server.py"
  local cmd = string.format("CODEPARTNER_API_KEY='%s' python %s &", M.config.api_key, server_script)
  vim.fn.system(cmd)
  print("CodePartner server started")
end

function M.stop_server()
  local plugin_dir = M.get_plugin_dir()
  local pid_file = plugin_dir .. "/server/codepartner_server.pid"

  -- Check if PID file exists
  if vim.fn.filereadable(pid_file) == 0 then
    print("CodePartner server is not running")
    return
  end

  -- Read PID from file
  local pid = vim.fn.readfile(pid_file)[1]

  -- Send SIGTERM to the process
  local cmd = string.format("kill %s", pid)
  vim.fn.system(cmd)

  -- Remove PID file
  os.remove(pid_file)

  print("CodePartner server stopped")
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  if not M.config.api_key then
    vim.api.nvim_err_writeln("CodePartner: API key is not set. Please configure it using require('codepartner').setup({api_key = 'your_api_key'})")
    return
  end

  if M.config.auto_start_server then
    M.check_python_requirements()
    if not M.is_server_running() then
      M.start_server()
    end
  end

  vim.opt.iskeyword:append("-")
  vim.api.nvim_create_user_command('ExplainSelection', function()
    M.show_explanation()
  end, {range = true})

  vim.api.nvim_create_user_command('StartCodePartner', function()
    M.start_server()
  end, {range = true})

  vim.api.nvim_create_user_command('StopCodePartner', function()
    M.stop_server()
  end, {range = true})

  -- Global keybindings
  vim.api.nvim_set_keymap('n', '<Leader>et', ':lua require("codepartner").toggle_explanation_window()<CR>', {noremap = true, silent = true})
  vim.api.nvim_set_keymap('n', '<Leader>ec', ':lua require("codepartner").close_explanation_window()<CR>', {noremap = true, silent = true})
end

function M.get_visual_selection()
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    local lines = vim.fn.getline(start_pos[2], end_pos[2])
    if #lines == 0 then
        return nil
    end
    if start_pos[2] == end_pos[2] then
        lines[1] = lines[1]:sub(start_pos[3], end_pos[3])
    else
        lines[1] = lines[1]:sub(start_pos[3])
        lines[#lines] = lines[#lines]:sub(1, end_pos[3])
    end
    return table.concat(lines, "\n")
end

local function escape_for_json(text)
    if text == nil then
        return nil
    end

    local escaped = text:gsub('[%z\1-\31\\"]', function(c)
        local replacements = {
            ['\0'] = '\\u0000', ['\t'] = '\\t',
            ['\n'] = '\\n', ['\r'] = '\\r',
            ['"']  = '\\"', ['\\'] = '\\\\'
        }
        return replacements[c] or string.format('\\u%04x', c:byte())
    end)

    return escaped
end

function M.call_explanation_api(text, query, callback)
    M.append_to_buffer(M.explanation_buf, "\n\nGenerating response...\n\n")

    local escaped_text = ""
    local escaped_query = ""

    if text ~= nil then
      escaped_text = escape_for_json(text)
      -- escaped_text = text:gsub("[\"'\n]", {
      --     ['"'] = '\\"',
      --     ["'"] = "'\\''",
      --     ["\n"] = "\\n"
      -- })
    end

    if query ~= nil then
      escaped_query = escape_for_json(query)
      -- escaped_query = query:gsub("[\"'\n]", {
      --     ['"'] = '\\"',
      --     ["'"] = "'\\''",
      --     ["\n"] = "\\n"
      -- })
    end

    local request_body = string.format('{"text": "%s", "query": "%s", "conversation_id": "%s"}',
    escaped_text, escaped_query, M.conversation_id)

    local cmd = string.format([[curl -v -X POST -H "Content-Type: application/json" --data '%s' %s/explain]],
    request_body, M.config.server_url)

    local full_response = ""
    local job_id = vim.fn.jobstart(cmd, {
        on_stdout = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    if line ~= "" then
                        full_response = full_response .. line .. "\n"
                    end
                end
            end
        end,
        on_stderr = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    if line ~= "" then
                        print("Error: " .. line)
                    end
                end
            end
        end,
        on_exit = function(_, exit_code)
            if exit_code ~= 0 then
                print("API call failed with exit code: " .. exit_code)
                M.append_to_buffer(M.explanation_buf, "API CALL FAILED! MAKE SURE CODEPARTNER SERVER IS RUNNING!")
                callback(nil)
            else
                callback(full_response)
            end
        end,
    })
    if job_id == 0 then
        print("Invalid arguments in jobstart()")
        callback(nil)
    elseif job_id == -1 then
        print("Command is not executable")
        callback(nil)
    end
end

function M.prompt_for_follow_up()
    local width = vim.api.nvim_win_get_width(0) - 1
    local prompt_text = "\nEnter your follow-up question (or press Esc to exit):\n"
    local prompt =  string.format("%s\n%s", string.rep("─", width), prompt_text)
    M.append_to_buffer(M.explanation_buf, prompt)
    -- Get the last line number of the buffer
    local last_line = vim.api.nvim_buf_line_count(M.explanation_buf)
    -- Move the cursor to the line below the prompt
    vim.api.nvim_win_set_cursor(0, {last_line, 0})
    -- Set up autocmd to capture user input
    vim.cmd([[
        augroup ExplanationPrompt
            autocmd!
            autocmd InsertEnter <buffer> lua require('codepartner').setup_insert_mapping()
        augroup END
    ]])
    vim.api.nvim_command("startinsert")
end

function M.setup_insert_mapping()
    vim.api.nvim_buf_set_keymap(0, 'i', '<CR>', '', {
        noremap = true,
        silent = true,
        callback = function()
            M.handle_user_input()
        end
    })
end

function M.handle_user_input()
    local query = vim.api.nvim_get_current_line()
    vim.api.nvim_buf_set_lines(M.explanation_buf, -1, -1, false, {})  -- Remove the input line
    -- Clear the autocommand group and keymap
    vim.cmd([[
        augroup ExplanationPrompt
            autocmd!
        augroup END
    ]])
    vim.api.nvim_buf_del_keymap(0, 'i', '<CR>')
    -- Exit insert mode
    vim.api.nvim_command("stopinsert")
    -- Process the query
    M.conversation_history[#M.conversation_history + 1] = {type = "query", content = query}
    M.send_follow_up_query(query)
end

function M.send_follow_up_query(query)
    M.call_explanation_api(nil, query, function(response)
        if response then
            M.conversation_history[#M.conversation_history + 1] = {type = "response", content = response}
            M.display_conversation_history()
            M.prompt_for_follow_up()
        else
            M.append_to_buffer(M.explanation_buf, "Failed to get explanation from API\n")
        end
    end)
end


local function horizontal_line()
    local width = vim.api.nvim_win_get_width(0) - 1
    return string.format("%s", string.rep("─", width))
end

function M.display_conversation_history()
    vim.api.nvim_buf_set_lines(M.explanation_buf, 0, -1, false, {})
    M.append_to_buffer(M.explanation_buf, ("[CONVERSATION_ID: %s]\n\n"):format(M.conversation_id))
    for _, item in ipairs(M.conversation_history) do
        if item.type == "explanation" then
            M.append_to_buffer(M.explanation_buf, "EXPLANATION")
            M.append_to_buffer(M.explanation_buf, horizontal_line())
            M.append_to_buffer(M.explanation_buf, "  " .. item.content:gsub("\n", "\n  ") .. "\n")
        elseif item.type == "query" then
            M.append_to_buffer(M.explanation_buf, "YOUR QUESTION:")
            M.append_to_buffer(M.explanation_buf, horizontal_line())
            M.append_to_buffer(M.explanation_buf, "  " .. item.content:gsub("\n", "\n  ") .. "\n")
        elseif item.type == "response" then
            M.append_to_buffer(M.explanation_buf, "RESPONSE:")
            M.append_to_buffer(M.explanation_buf, horizontal_line())
            M.append_to_buffer(M.explanation_buf, "  " .. item.content:gsub("\n", "\n  ") .. "\n")
        end
    end
end


function M.append_to_buffer(buf, text)
    local lines = vim.split(text, "\n")
    local line_count = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_buf_set_lines(buf, line_count, -1, false, lines)
end


function M.show_explanation()
    local selected_text = M.get_visual_selection()
    if not selected_text then
        print("No text selected")
        return
    end

    -- Close existing window if it exists
    M.close_explanation_window()

    M.create_float_window()

    -- Clear previous explanation content
    M.conversation_history = {}

    -- Generate a new conversation ID
    M.conversation_id = tostring(os.time())

    -- Set buffer options
    vim.api.nvim_buf_set_option(M.explanation_buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(M.explanation_buf, 'filetype', 'markdown')

    local user_query = vim.fn.input("Enter your query (optional): ")
    local conv_type = "explanation"
    if user_query and user_query ~= "" then
      conv_type = "response"
    end

    M.call_explanation_api(selected_text, user_query, function(response)
        if response then
            M.conversation_history[#M.conversation_history + 1] = {type = conv_type, content = response}
            M.display_conversation_history()
            M.prompt_for_follow_up()
        else
            M.append_to_buffer(M.explanation_buf, "Failed to get explanation from API\n")
        end
    end)
end


function M.get_theme_colors()
    local background = "dark"

    -- local dialog_bg = "#22092C"
    -- local dialog_fg = "#BED754"

    local bg = "#1c1c1c"  -- dark background
    local fg = "#d0d0d0"  -- light text
    local border = "#585858"  -- medium grey border

    -- local dialog_bg = "#03055B"  -- Dark navy blue
    -- local dialog_fg = "#FFFF99"  -- Pale yellow

    -- **1. Dark Navy and Light Gray**
    -- local dialog_bg = "#03055B"  -- Dark navy blue
    -- local dialog_fg = "#CCCCCC"  -- Light gray
    --
    -- **2. Charcoal and Mint**
    -- local dialog_bg = "#333333"  -- Charcoal gray
    -- local dialog_fg = "#B2FFFC"  -- Mint green
    --
    -- **3. Midnight Blue and Cream**
    -- dialog_bg = "#1A1D23"  -- Midnight blue
    -- dialog_fg = "#F5F5DC"  -- Cream
    --
    -- **4. Dark Gray and Neon Green**
    -- local dialog_bg = "#2F2F2F"  -- Dark gray
    -- local dialog_fg = "#33CC33"  -- Neon green
    --
    -- **5. Navy Blue and Gold**
    -- local dialog_bg = "#030074"  -- Navy blue
    -- local dialog_fg = "#FFD700"  -- Gold
    --
    -- **6. Dark Purple and Pale Yellow**
    -- local dialog_bg = "#3B3F54"  -- Dark purple
    -- local dialog_fg = "#FFFF99"  -- Pale yellow
    --
    -- **7. Black and White**
    -- local dialog_bg = "#000000"  -- Black
    -- local dialog_fg = "#FFFFFF"  -- White
    --
    -- **8. Dark Brown and Light Orange**
    -- local dialog_bg = "#452B1F"  -- Dark brown
    -- local dialog_fg = "#FFC107"  -- Light orange
    --
    -- **9. Teal and Coral**
    -- local dialog_bg = "#0097A7"  -- Teal
    -- local dialog_fg = "#FFC67D"  -- Coral
    --
    -- **10. Dark Green and Light Blue**
    -- local dialog_bg = "#2F4F4F"  -- Dark green
    -- local dialog_fg = "#87CEEB"  -- Light blue

    -- Additional colors inspired by the image
    local keyword_color = "#F38BA8"  -- Soft pink for keywords
    local string_color = "#A6E3A1"   -- Muted green for strings
    local number_color = "#FAB387"   -- Soft orange for numbers
    local function_color = "#89B4FA" -- Light blue for functions
    local comment_color = "#6C7086"  -- Grayish for comments
    local type_color = "#89DCEB"     -- Cyan for types

    return dialog_bg, dialog_fg, border, keyword_color, string_color, number_color, function_color, comment_color, type_color
end

function M.create_float_window()
    local buf = vim.api.nvim_create_buf(false, true)
    local width = vim.api.nvim_get_option("columns")
    local height = vim.api.nvim_get_option("lines")

    local win_height = math.ceil(height) - 4
    local win_width = math.ceil(width * 0.5)

    local opts = {
        style = "minimal",
        relative = "editor",
        width = win_width,
        height = win_height,
        row = 2,
        col = width - win_width - 2,
        border = "rounded"
    }

    local win = vim.api.nvim_open_win(buf, true, opts)

    -- Apply the theme colors
    local bg, fg, border = M.get_theme_colors()
      -- Set all necessary highlight groups
    vim.cmd(string.format([[
        highlight MyFloatNormal guibg=%s guifg=%s
        highlight MyFloatEndOfBuffer guibg=%s guifg=%s
        highlight MyFloatSignColumn guibg=%s
        highlight MyFloatBorder guifg=%s guibg=%s
        highlight MyFloatCursorLine guibg=#303030
    ]], bg, fg, bg, bg, bg, border, bg))

    -- Apply highlights to all window areas
    vim.api.nvim_win_set_option(win, 'winhl', table.concat({
        'Normal:MyFloatNormal',
        'EndOfBuffer:MyFloatEndOfBuffer',
        'SignColumn:MyFloatSignColumn',
        'NormalFloat:MyFloatNormal',
        'FloatBorder:MyFloatBorder',
        'CursorLine:MyFloatCursorLine'
    }, ','))


    -- vim.cmd(string.format("highlight MyFloatNormal guibg=%s guifg=%s", bg, fg))
    -- vim.api.nvim_win_set_option(win, 'winhl', 'Normal:MyFloatNormal')

    vim.api.nvim_buf_set_option(buf, 'modifiable', true)
    vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')

    -- Set window options for better Markdown viewing
    vim.api.nvim_win_set_option(win, 'wrap', true)
    vim.api.nvim_win_set_option(win, 'linebreak', true)
    vim.api.nvim_win_set_option(win, 'breakindent', true)
    vim.api.nvim_win_set_option(win, 'breakindentopt', 'shift:2')
    vim.api.nvim_win_set_option(win, 'sidescrolloff', 5)
    vim.api.nvim_win_set_option(win, 'scrolloff', 2)

    -- Store references globally
    M.explanation_win = win
    M.explanation_buf = buf

    -- Set up local keybindings for the explanation buffer
    local keymap_opts = { noremap = true, silent = true }
    vim.api.nvim_buf_set_keymap(M.explanation_buf, 'n', 'q', ':lua require("codepartner").close_explanation_window()<CR>', keymap_opts)
    vim.api.nvim_buf_set_keymap(M.explanation_buf, 'n', '<Esc>', ':lua require("codepartner").close_explanation_window()<CR>', keymap_opts)

    return buf, win
end

function M.close_explanation_window()
    if M.explanation_win and vim.api.nvim_win_is_valid(M.explanation_win) then
        vim.api.nvim_win_close(M.explanation_win, true)
    end
    if M.explanation_buf and vim.api.nvim_buf_is_valid(M.explanation_buf) then
        vim.api.nvim_buf_delete(M.explanation_buf, {force = true})
    end
    M.explanation_win = nil
    M.explanation_buf = nil
end

function M.toggle_explanation_window()
    if M.explanation_win and vim.api.nvim_win_is_valid(M.explanation_win) then
        M.close_explanation_window()
    elseif #M.conversation_history > 0 then
        -- If we have content, create a new window and buffer
        M.create_float_window()
        M.display_conversation_history()
        M.prompt_for_follow_up()
    else
        -- If we have no content at all, inform the user
        vim.api.nvim_echo({{"\nNo explanation content available.", "WarningMsg"}}, false, {})
    end
end

return M
