test: main.mm
	clang++ -O2 main.mm -framework Cocoa -framework OpenGL -o test
