if [ "$1" == "no" ]; then
	./build/lin/odinengine
else
	./cmpshaders.sh
	odin run src -debug -define:PROFILE=0 -define:EDITOR=true
	# odin run src -o:speed -no-bounds-check -define:EDITOR=true -define:PROFILE=0
fi
