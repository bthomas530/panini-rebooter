# Creating Self-Contained Panini Manager Automator App

## Steps to Create the App:

1. **Open Automator**
   - Press `Cmd + Space` and search for "Automator"
   - Click "New Document"
   - Select "Application" and click "Choose"

2. **Add Terminal Action**
   - In the Library panel on the left, search for "Run Shell Script"
   - Drag "Run Shell Script" to the workflow area on the right

3. **Configure the Shell Script**
   - Set "Shell" dropdown to `/bin/bash`
   - Set "Pass input" dropdown to "as arguments"
   - Replace the default script content by copying the ENTIRE contents of `automator-script-embedded.sh`
   - This embeds the complete Panini management script directly in the app - no external files needed!

4. **Save the Application**
   - Press `Cmd + S`
   - Name it "Panini Manager"
   - Choose where to save it (Desktop or Applications folder recommended)
   - Click "Save"

## Usage:

- Double-click the "Panini Manager" app
- It will open Terminal with a clean interface
- It will prompt for your password (sudo required)
- The interactive menu will appear for managing the Panini Everest Engine
- The terminal window will stay open until you press Enter after the script completes

## Benefits of This Approach:

✅ **Completely Self-Contained** - No external file dependencies
✅ **Portable** - Can be copied to any Mac and will work
✅ **Simple** - Just one double-click to launch
✅ **No Path Issues** - Doesn't rely on file locations
✅ **Easy Updates** - Just edit the Automator app to update the script

## Alternative Quick Launch Version:

If you want separate apps for each action, you can create additional Automator apps with these scripts:

### Start Service App:
```bash
#!/bin/bash
PANINI_SCRIPT="/Users/bthomas/dev/GitHub/zOLD/panini-rebooter/panini-rebooter.sh"
sudo "$PANINI_SCRIPT" start
read -p "Press Enter to close..."
```

### Stop Service App:
```bash
#!/bin/bash
PANINI_SCRIPT="/Users/bthomas/dev/GitHub/zOLD/panini-rebooter/panini-rebooter.sh"
sudo "$PANINI_SCRIPT" stop
read -p "Press Enter to close..."
```

### Status Check App:
```bash
#!/bin/bash
PANINI_SCRIPT="/Users/bthomas/dev/GitHub/zOLD/panini-rebooter/panini-rebooter.sh"
sudo "$PANINI_SCRIPT" status
read -p "Press Enter to close..."
``` 