if [ "$1" == "no" ]; then
	./build/lin/odinengine
else
	./cmpshaders.sh
	odin run src -debug -define:PROFILE=0
	# odin run src -o:speed -no-bounds-check -define:PROFILE=2
fi
