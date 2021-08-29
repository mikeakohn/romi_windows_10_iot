
PROGRAM=romi

default: $(PROGRAM).hex

$(PROGRAM).hex: $(PROGRAM).asm
	naken_asm -l -I/storage/devkits/atmel -o $(PROGRAM).hex $(PROGRAM).asm

program:
	avrdude -c avr109 -p atmega32u4 -P /dev/ttyACM0 -v -U flash:w:$(PROGRAM).hex

install: $(PROGRAM).hex
	cp $(PROGRAM).hex /storage/samba/hexfiles/

clean:
	@rm -f *.hex
	@rm -f *.lst
	@echo "Clean!"

