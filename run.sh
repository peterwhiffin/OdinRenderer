if [ "$1" == "no" ]; then
	./build/lin/odinengine
else
	./cmpshaders.sh
	# odin run src -debug
	odin run src -o:speed
fi
