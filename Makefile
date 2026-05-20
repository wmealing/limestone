# On Fedora/Arch the mount point is /run/media/$(USER)/RPI-RP2
export RP2 = /media/$(USER)/RPI-RP2
export DEVICE = /dev/ttyACM0

first-touch: prep-image delay flash-client
	@echo "FIRST TOUCH COMPLETE"

update-tags: 
	/opt/homebrew/Cellar/universal-ctags/6.2.1/bin/ctags -R . 

delay:
	@sleep 3

long-delay:
	@sleep 5

# this is fragile, i think i gotta hold down the button on the device. 
prep-image:
	@echo "Welcome to simple flasher, connect your RP2040"
	@echo "REBOOTING DEVICE (please wait)"
	@picotool reboot -f  -u
	@echo "Please wait..."
	@sleep 3
	@rsync -v --progress ./data/AtomVM*.uf2 $$RP2
	@echo "Please wait..."
	@sleep 3
	@echo "REBOOTING DEVICE (please wait)"
	@picotool reboot -f -u
	@echo "Please wait..."
	@sleep 5
	@rsync -v --progress ./data/atomvmlib*.uf2 $$RP2
	@echo "COMPLETE"

flash-client: 
	@echo "Flashing erlang code"
	@picotool reboot -f  -u
	@echo "Please wait..."
	@sleep 3
	@rebar3 atomvm pico_flash	
	@echo "COMPLETE"

build-image:
	rebar3 compile 

observe:
	screen $$DEVICE


devel: build-image flash-client long-delay observe
