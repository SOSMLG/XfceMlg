# dock like config be like
# the first 3 checked 2 not , 2 last are checked
# active color #007ACC and inactive color 3A506B
# removing firefox 
sudo apt purge firefox 
sudo apt autoremove
# installing ohmybash and replacing firefox with firefox-esr
sudo apt install firefox-esr vlc fonts-font-awesome git exa zoxide  linux-headers-amd64 firmware-iwlwifi firmware-misc-nonfree libreoffice fonts-noto-extra fonts-noto-color-emoji 
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

#!/bin/bash

git clone https://github.com/vinceliuice/Graphite-gtk-theme.git || exit 1
cd Graphite-gtk-theme || exit 1

./install.sh -t purple --tweaks rimless darker  -d "$THEME_DIR"

cd ..

git clone --depth=1 https://github.com/vinceliuice/Colloid-icon-theme.git
cd Colloid-icon-theme
./install.sh -d "$ICON_DIR" 
cd ..

rm -rf Graphite-gtk-theme Colloid-icon-theme

echo "✅ Installation complete! Apply the themes using your system's appearance settings."

#!/bin/bash

# Create fonts directory if it doesn't exist
mkdir -p ~/.local/share/fonts

# Temp file for download
TMP_FONT="/tmp/HackNerdFont-Regular.ttf"

echo "📦 Downloading Hack Nerd Font (Powerline + Nerd icons)..."
curl -fLo "$TMP_FONT" \
  https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/Hack/Regular/complete/Hack%20Nerd%20Font%20Complete.ttf

if [ -f "$TMP_FONT" ]; then
    mv "$TMP_FONT" ~/.local/share/fonts/
    echo "✅ Font moved to ~/.local/share/fonts"
else
    echo "❌ Download failed. Exiting."
    exit 1
fi

# Refresh font cache
echo "🔄 Updating font cache..."
fc-cache -fv > /dev/null

# Remove temp file just in case
rm -f "$TMP_FONT"

echo "🎉 Done! Set your terminal font to 'Hack Nerd Font' to use Agnoster + exa icons properly."

