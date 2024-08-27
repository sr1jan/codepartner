# CodePartner.nvim

CodePartner is a Neovim plugin that provides AI-powered code explanations and assistance directly in your editor.

## Features

- Explain selected code snippets
- Follow-up questions and conversations about your code
- Customizable floating window for explanations

https://github.com/user-attachments/assets/789ad4f8-06c1-466b-b145-6fa47e7e3963


## Requirements

- Neovim >= 0.7.0
- Python 3.7+
- Flask 
- llm >= 0.14

## Installation

Here are several ways to install CodePartner.nvim:

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'sr1/codepartner.nvim',
  config = function()
    require('codepartner').setup({
      api_key = 'your_api_key_here',
      server_url = 'http://localhost:5000'  -- Adjust if needed
      auto_start_server = true  -- Set to false if you want to start the server manually
    })
  end
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

Add the following to your init.vim:

```vim
Plug 'sr1/codepartner.nvim'

" After plug#end():
lua << EOF
require('codepartner').setup({
  api_key = 'your_api_key_here',
  server_url = 'http://localhost:5000'  -- Adjust if needed
  auto_start_server = true  -- Set to false if you want to start the server manually
})
EOF
```

### Using [dein.vim](https://github.com/Shougo/dein.vim)

Add the following to your init.vim:

```vim
call dein#add('sr1/codepartner.nvim')

" After dein#end():
lua << EOF
require('codepartner').setup({
  api_key = 'your_api_key_here',
  server_url = 'http://localhost:5000'  -- Adjust if needed
  auto_start_server = true  -- Set to false if you want to start the server manually
})
EOF
```

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

Add the following to your Neovim configuration:

```lua
{
  'sr1/codepartner.nvim',
  config = function()
    require('codepartner').setup({
      api_key = 'your_api_key_here',
      server_url = 'http://localhost:5000'  -- Adjust if needed
      auto_start_server = true  -- Set to false if you want to start the server manually
    })
  end
}
```

### Manual Installation

If you prefer to manually install the plugin:

1. Clone the repository:
   ```
   git clone https://github.com/sr1/codepartner.nvim.git \
     ~/.local/share/nvim/site/pack/plugins/start/codepartner.nvim
   ```
2. Add the following to your init.lua:
   ```lua
   require('codepartner').setup({
     api_key = 'your_api_key_here',
     server_url = 'http://localhost:5000'  -- Adjust if needed
     auto_start_server = true  -- Set to false if you want to start the server manually
   })
   ```

## Usage

1. Select the code you want to explain in visual mode
2. Run `:ExplainSelection` to get an explanation
3. Use `<Leader>et` to toggle the explanation window
4. Use `<Leader>ec` to close the explanation window

## Configuration

You can customize the plugin by passing options to the setup function:

```lua
require('codepartner').setup({
  api_key = 'your_api_key_here',
  server_url = 'http://your_server_url:port'
  auto_start_server = true  -- Set to false if you want to start the server manually
})
```

## Server Management

By default, the server will start automatically when you open Neovim. You can manage the server using the following commands:

To start the server manually:
```vim
:StartCodePartner()
```

To stop the server:
```vim
:StopCodePartner()
```

The server runs as a background process. You can find its logs in the plugin's server directory (codepartner_server.log).


