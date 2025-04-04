# removing uncessary files 
sudo apt remove --purge xfdesktop4
sudo apt remove -y xfdesktop4 xfwm4  xfce4-settings i3blocks dmenu && sudo apt autoremove -y
#making Directory for I3
mkdir -p .i3
cp config ~/.i3/config
