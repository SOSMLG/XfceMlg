#BackPorts For Trixie 
"deb http://deb.debian.org/debian/ trixie-backports main non-free-firmware"
"deb-src http://deb.debian.org/debian/ trixie-backports main non-free-firmware"
# 32 Bit Architecture Support
sudo dpkg --add-architecture i386
# flatpack configuration 
sudo apt update -yy
sudo apt upgrade -yy
sudo apt install flatpak -yy
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
# installing Other Apps 
sudo apt install vlc micro libreoffice tilix fastfetch unzip cargo p7zip ntfs-3g eza zoxide vlc gimp imagemagick docklike-plugin  xfce4-panel-profiles fzf ffmpeg fonts-firacode fonts-jetbrains-mono fonts-croscore fonts-crosextra-carlito fonts-crosextra-caladea fonts-noto fonts-noto-cjk git extrepo -yy
sudo apt purge nano firefox-esr -yy
sudo apt autoremove
# librewolf
sudo extrepo enable librewolf 
sudo apt update && sudo apt install librewolf -y
#fonts 
git clone https://github.com/powerline/fonts.git 
cd fonts   
./install.sh    
wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/FiraCode.zip
unzip FiraCode.zip -d ~/.local/share/fonts
fc-cache -fv
#micro plugins 
micro -plugin install filemanager  
micro -plugin install fzf           
micro -plugin install quoter        
micro -plugin install autoclose     
micro -plugin install detectindent  
micro -plugin install linter        
micro -plugin install go            
micro -plugin install fish
#pipx 
sudo apt install pipx 
pipx install pywal 
# Oh My Bash
bash -c "$(wget https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh -O -)"

