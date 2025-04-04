# dock like config be like
# the first 3 checked 2 not , 2 last are checked
# active color #007ACC and inactive color 3A506B
# removing firefox 
sudo apt purge firefox 
sudo apt autoremove
# installing ohmybash and replacing firefox with firefox-esr
sudo apt install firefox-esr vlc fonts-font-awesome fonts-terminus telegram-desktop exa zoxide  linux-headers-amd64 firmware-iwlwifi firmware-misc-nonfree libreoffice fonts-noto-extra fonts-noto-color-emoji i3-wm
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"
#paste this in xfce4-pannel 0a0b12
#pasting my own config 
sudo cp gtk.css ~/.config/gtk-3.0/gtk.css
sudo cp .bashrc ~/.bashrc
sudo cp terminalrc ~/.config/xfce4/terminal/terminalrc
sudo cp .nanorc ~/.nanorc 
sudo cp .nanorc /root/
# install theme and icons 
#!/bin/bash

THEME_DIR="$HOME/.themes"
ICON_DIR="$HOME/.icons"

mkdir -p "$THEME_DIR" "$ICON_DIR"

git clone --depth=1 https://github.com/vinceliuice/Orchis-theme.git
cd Orchis-theme
./install.sh -d "$THEME_DIR" 
cd ..

git clone --depth=1 https://github.com/vinceliuice/Colloid-icon-theme.git
cd Colloid-icon-theme
./install.sh -d "$ICON_DIR" 
cd ..

rm -rf Orchis-theme Colloid-icon-theme

echo "✅ Installation complete! Apply the themes using your system's appearance settings."
# fonts 
#!/bin/bash

# Define font directories for user and root
USER_FONT_DIR="$HOME/.local/share/fonts"
ROOT_FONT_DIR="/root/.local/share/fonts"

# Create font directories if they don't exist
mkdir -p "$USER_FONT_DIR"
sudo mkdir -p "$ROOT_FONT_DIR"

# List of essential Nerd Fonts
FONTS=("JetBrainsMono" "FiraCode" "Hack" "DejaVuSansMono" "UbuntuMono")

# Download and install fonts
for FONT in "${FONTS[@]}"; do
    echo "Downloading $FONT Nerd Font..."
    wget -q --show-progress "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${FONT}.zip" -O "/tmp/${FONT}.zip"
    
    echo "Extracting $FONT..."
    unzip -q "/tmp/${FONT}.zip" -d "$USER_FONT_DIR"
    
    # Copy to root's font directory as well
    sudo cp -r "$USER_FONT_DIR" "$ROOT_FONT_DIR"

    # Remove zip file to save space
    rm "/tmp/${FONT}.zip"
done

# Refresh font cache for both user and root
fc-cache -fv
sudo fc-cache -fv

echo "✅ Essential Nerd Fonts installed successfully!"
#xfce4 tweaks 
#!/bin/bash

echo "✅Everything is installed :D Time To Reboot "


