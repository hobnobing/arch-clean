## Arch Clean

Simple script that:
* Removes orphan packages
* Cleans Pacman cache
* Cleans AUR helper cache
* Vacuums systemd logs
* Clears coredumps
* Uninstalls unused Flatpak runtimes
* Prunes unused Docker assets
* Purges user cache
* Removes broken systemlinks
* Checks config files for unmerged .pacnew or .pacsave
* Displays disk usage

The script does not prompt for each step, everything above will happen automatically.


## Installation
```
curl -sSL https://raw.githubusercontent.com/hobnobing/arch-clean/main/arch-clean.sh | sudo tee /usr/local/bin/arch-clean > /dev/null && sudo chmod +x /usr/local/bin/arch-clean
```

## Manual Installation

```
git clone https://github.com/hobnobing/arch-clean.git
cd arch-clean
sudo mv arch-clean.sh /usr/local/bin/arch-clean
sudo chmod +x /usr/local/bin/arch-clean
```
## Usage
```bash
sudo arch-clean
```
