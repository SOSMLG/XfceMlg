# dock like config be like
# the first 3 checked 2 not , 2 last are checked
# active color #007ACC and inactive color 3A506B
# removing firefox 
sudo apt purge firefox 
sudo apt autoremove
# installing ohmybash and replacing firefox with firefox-esr
sudo apt install firefox-esr vlc fonts-font-awesome  exa zoxide  linux-headers-amd64 firmware-iwlwifi firmware-misc-nonfree libreoffice fonts-noto-extra fonts-noto-color-emoji i3-wm
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
