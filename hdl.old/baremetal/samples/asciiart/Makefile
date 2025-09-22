PROGRAM=asciiart

PATH:=/usr/local/pdp11-aout/bin:${PATH}

all:
	pdp11-aout-gcc -c ${PROGRAM}.c -o ${PROGRAM}.o
	pdp11-aout-as start.S -o start.o
	pdp11-aout-ld -T ld.scr start.o ${PROGRAM}.o -o ${PROGRAM}.out
	bin2load -a -f ${PROGRAM}.out -o ${PROGRAM}.lda
	./out2rom.pl ${PROGRAM}.out > rom.${PROGRAM}.v

clean:
	rm *.lda
	rm *.out
	rm *.o
	rm *.v
