# Odysseus Dashboard

A powershell dashboard designed for [Odysseus AI](https://github.com/odysseus-dev/odysseus) for use with the Native Windows version.
Created for self use, but should be easy to add and customize to meet any basic Native Windows setup.


- [Set up](#setup)
- [Options](#options)
- [Preflight](#preflight-options)
- [Postflight](#postflight-options)
- [Adding New Options](#adding-options--preflights--postflights)


## Setup

1. Download zip and extract to odysseus root folder

Default File Layout
```plaintext 
.
├── create_shortcuts.bat
├── dashboard-config.ps1
├── dashboard-settings.ps1
├── dashboard.ps1
├── order.json
├── run-dashboard.bat
├── .github/
│   ├── README.md
├── dashboard-dependencies/
│   ├── calendar-config.json
│   ├── create_portable.py
│   ├── sync_proton.py
│   └── icons/
│       └── start-icon.ico
├── dashboard-handlers/
│   ├── postflight/
│   │   ├── close-odysseus-web.ps1
│   │   └── purge-temp.ps1
│   ├── postflight-disabled/
│   │   ├── stop-chromadb.ps1
│   │   ├── stop-ollama.ps1
│   │   └── stop-proton-bridge.ps1
│   ├── preflight/
│   │   ├── backup-database.ps1
│   │   └── open-odyseus-web.ps1
│   └── preflight-disabled/
│       ├── cuda-env.ps1
│       ├── start-chromadb.ps1
│       ├── start-ollama.ps1
│       ├── start-proton-bridge.ps1
│       └── sync-proton.ps1
├── dashboard-options/
│   ├── create-portable.ps1
│   ├── odysseus.ps1
│   └── shutdown-all.ps1
├── dashboard-options-disabled/
│   ├── chromadb.ps1
│   ├── manage-ollama/
│   │   ├── main.ps1
│   │   └── sub/
│   │       └── model-editor.ps1
│   ├── ollama.ps1
│   ├── proton-bridge.ps1
│   ├── stable-diffusion.ps1
│   └── sync-proton-calendar.ps1
├── dashboard-services/
│   ├── OdysseusLauncher.ps1
│   └── service-helpers.ps1
└── dashboard-templates/
    ├── action-option.ps1
    ├── preflight-postflight.ps1
    ├── toggle-option.ps1
    ├── ascii/
    │   ├── ascii-headers.ps1
    │   └── headers/
    │       ├── inspector.txt
    │       ├── logs.txt
    │       ├── network.txt
    │       ├── odysseus.txt
    │       ├── ollama.txt
    │       ├── proton.txt
    │       ├── python.txt
    │       ├── services.txt
    │       ├── settings.txt
    │       ├── stablediffusion.txt
    │       ├── status.txt
    │       ├── task.txt
    │       ├── template.txt
    │       ├── terminal.txt
    │       └── welcome.txt
    └── interactive-ui/
        ├── main.ps1
        └── sub/
            └── sub-ui.ps1
```

    


2. Review `dashboard-config.ps1` to adjust Ports and Hosts

| Service | Default Host | Default Port | Target |
| :--- | :---: | :---: | :---: |
| Odysseus AI | `127.0.0.1` | `7000` | `./launch-windows.ps1` |
| Stable Diffusion | `127.0.0.1` | `8001` | External or local SD web UI process |
| Chromadb | `127.0.0.1` | `8100` | `.\venv\Scripts\chroma.exe` |
| Proton Bridge | `127.0.0.1` | `1143` | `proton-bridge.exe` |
| Ollama | `127.0.0.1` | `11434` | `ollama.exe` |

3. OPTIONAL: Generate Desktop Shortcut
Run the `create-shortcuts.bat` to create a desktop shortcut to run `run-dashboard.bat` 
with icon `dashboard-dependencies/icons/start-icon.ico` as the icon

4. Run Odysseus Dashboard
Run using `run-dashboard.dat` or the desktop shortcut `Odysseus Dashboard` if created.


## Options
### Enabling Options
Out of the box Odysseus Launcher, Create Portable and Shutdown all are the only options loaded.
To enable other options there are 2 methods

1. **Dashboard Settings Method**
- Run dashboard
- Click <kbd>ESC</kbd> to open dashboard settings
- Use space to toggle `Enabled` or `Disabled` state for each
- Use <kbd>w</kbd> and <kbd>s</kbd> to change the order of the dashboard
- Click <kbd>ESC</kbd> to return to the dashboard

2. **Manual Method**

open to `dashboard-options-disabled/` folder
manually move files into `dashboard-options/` to enable them
OPTIONAL: update `order.json` to change the order they appear.

### Default Options
**Odysseus Launcher**: Toggles Odysseus on or off. 
Runs preflight options then runs `launch-windows.ps1` to start.
Runs postflight options and then stops the port to stop.


**Shutdown All**: Shuts down all services and runs postflight options.


**Create Portable**: Creates a portable Odysseus Launcher with the IP of the host machine autoset. Portable includes a run script, create-shortcut script and icon.
For use with remoting into odysseus from secondary machines.

### Available Options
Options that are available but disabled by default

**Chromadb**: Adds own chromadb to Odysseus, added as a self fix to errors I encountered from the default Odysseus Chromadb.


**Ollama**: Toggles Ollama service on or off.
> [!NOTE]
> Requires Ollama to be installed


**Manage Ollama**: Interactive UI to view your Ollama models installed, view Ollama online register to install models.
Displays what models are active, VRAM use, size use. Allows you to stop/start models and edit their Parameters.
Opening the manager with Ollama disabled will cause Ollama to be auto-started.


**Stable Diffusion**: Runs stable-diffusion-3.5-medium, requires NVidia GPU with CUDA support due to `set CUDA_VISIBLE_DEVICES=0`


**Sync Proton Calendar**: Runs a one-way sync to from Proton Calendar to Odysseus Calendar, comes with support for Canadian Holidays. Added to allow Proton Calendar users to
sync their calendar to Odysseus
> [!NOTE]
> Requires you add your Proton Calendar share with everyone link at "dashboard-dependencies\calendar-config.json"
> This is a one-way sync, Odysseus side will not effect Proton Calendar side.
> Requires Manually to be run, has a preflight option available.


## Preflight Options
Preflight options will always be run before starting Odysseus when launching using the dashboard.

Has 2 preflight options available by default, others are under `dashboard-handlers/preflight-disabled/` folder.
They can be enabled by running dashboard, opening settings <kbd>ESC</kbd> and clicking <kbd>m</kbd> to switch to preflight.
Use <kbd>W</kbd> and <kbd>S</kbd> to change the order they are run in.

### Default Preflight

**Open Odysseus Web UI**: Opens Odysseus AI as a webui using your default browser when possible.
Stores browser profile at `C:\Users\<User>\AppData\Local\Odysseus\browser-profile`

- Supports browsers:
- Edge
- Chrome
- Brave
- Vivaldi
- Opera
- Arc
- Firefox
- Librewolf
- Floorp
- Zen


**Backup database**: Creates backups of the SQlite and Chromadb to a `backups` folder found at the root folder for odysseus.


### Available Preflight

**Cuda Env**: Self fix for CUDA errors encountered from default Odysseus setup.


**Start Ollama**: Starts Ollama service if not already started.


**Start Proton Bridge**: Starts Proton Bridge if not already started


**Sync Proton**: Runs the manual sync for Proton Calendar before start.


**Start Chromadb**: Starts the chromadb added by the Chromadb option. Not meant to be used if using the Odysseus AI chromadb default.


## Postflight Options
Postflight options will always be run after stopping Odysseus when stopped using the dashboard or when using the shutdown all option.

Has 2 postflight options available by default, others are under `dashboard-handlers/postflight-disabled/` folder.
They can be enabled by running dashboard, opening settings <kbd>ESC</kbd> and clicking <kbd>m</kbd> twice to switch to postflight.
Use <kbd>W</kbd> and <kbd>S</kbd> to change the order they are run in.

### Default Postflight

**Close Odysseus Web UI**: Auto closes the browser window opened if using the Preflight for opening a web ui for oddysseus.


**Purge Temps**: Purges Temp files that are located at `C:\Users\<User>\AppData\Local\Temp\` targeting `odysseus-app-profile`, `odysseus-tmux`, `scoped_dir*`, `playwright_*` and `pip-*`


### Available Postflight

**Stop Chromadb**: Stops chromadb added by the Chromadb option. Not meant to be used if using the Odysseus AI chromadb default.


**Stop Ollama**: Stops Ollama service.


**Stop Proton Bridge**: Stops Proton Bridge.



## Adding Options / Preflights / Postflights
Odysseus AI was meant for my own personal use so I expect features in here will not serve everyones needs.
It is meant to be easily customizable because of this so you can create your own dashboard options to meet your needs.


### Templates
I added template files to `dashboard-templates/`

`preflight-postflight.ps1`: simple template for preflight/postflights. They are meant to be open ended in their ability so purposely left mostly empty. 
Update the `TITLE: Name to display in settings` to change the name that is displayed when viewed in settings (Ex: `TITLE: Start Llama.cpp` will display `Start Llama.cpp` in settings).

`action-options.ps1`: Used for one time manual actions (Ex: proton sync to manually sync the calendar).

`toggle-options.ps1`: Used to toggle a service on or off (Ex: Ollama), if adding a new service be sure to add it to the `dashboard-config.ps1` file for easy use.

`interactive-ui/`: Folder to add interactive UI screens (Ex: Ollama Manager), `main.ps1` functions as the main UI that will be added to the dashboard
 with `sub/` folder there to hold any sub screens. ASCII art is available at `dashboard-templates/ascii/ascii-headers.ps1`.

Add to UI

```powershell
#Add Path
$asciiModule = Join-Path -Path $PSScriptRoot -ChildPath "dashboard-templates\ascii\ascii-headers.ps1"

#Test Path
if (Test-Path $asciiModule) {
    . $asciiModule
} else {
Write-Warning "ASCII Header module not found at: $asciiModule"
}

#Write Heading
Write-AsciiHeader -Name "<name>" -ForegroundColor <Colour>
```

add new ASCII art by adding `.txt` files to `dashboard-templates/ascii/headers/` folder, will use the filename as the ascii name.
OPTIONAL: Add alias by adding to ascii-headers alias
```powershell
$aliases = @{
        "chroma"  = "chromadb"
        "sd"      = "stablediffusion"
        "dash"    = "dashboard"
        "db"      = "database"
        "net"     = "network"
        "config"  = "settings"
        "log"     = "logs"
        "cli"     = "terminal"
        "stats"   = "analytics"
        "system"  = "status"
    }

```







