;; Romi - Copyright 2021 by Michael Kohn
;; Email: mike@mikekohn.net
;;   Web: http://www.mikekohn.net/
;;
;; Control a Pololu Romi over UART from a Raspberry Pi 3 running
;; Windows 10 Iot.

.avr8
.include "m32U4def.inc"

;; Looks like 16MHz crystal here.
;; avrdude: safemode: hfuse reads as D0
;; avrdude: safemode: efuse reads as C8
;; vrdude: safemode: Fuses OK (E:C8, H:D0, L:FF)

; r0  = 0
; r1  = 1
; r2  =
; r3  =
; r4  =
; r5  = divide by 2 interrupt count
; r6  =
; r7  =
; r16 =
; r17 = temp
; r18 = temp
; r19 = temp
; r20 = counter in interrupt
; r21 = temp in main
; r23 =
; r24 = function param 0
; r25 = Servo 20ms counter
; r26 = Servo value
; r30 =
; r31 =

; Command bytes>:
; <'f', 'b', 'l', 'r'> <count>

INTERRUPT_COUNT equ 60000
PIN_ENC_RIGHT equ 0
PIN_ENC_LEFT equ 2

;; PB pins.
MOTOR_RIGHT_DIR equ 1
MOTOR_RIGHT_SPEED equ 5
MOTOR_LEFT_DIR equ 2
MOTOR_LEFT_SPEED equ 6

.org 0x000
  rjmp start
.org 0x022
  rjmp timer1_match_a_interrupt

start:
  ;; Disable interrupts.
  cli

  ;; Setup some registers
  eor r0, r0   ; r0 = constant 0
  eor r1, r1   ; r1 = constant 1
  inc r1
  mov r5, r0

  ;; Set up PORTB, PORTC, PORTD
  ;; PB1 motor RIGHT DIR
  ;; PB2 motor LEFT DIR
  ;; PB4 motor LEFT encoder XOR
  ;; PB5 motor RIGHT SPEED
  ;; PB6 motor LEFT SPEED
  ;; PC7 LED YELLOW
  ;; PD5 LED GREEN
  ;; PE6 motor RIGHT encoder XOR
  ldi r17, 0x66
  out DDRB, r17
  out PORTB, r0
  ldi r17, 0x80
  out DDRC, r17
  out PORTC, r0
  ldi r17, 0x20
  out DDRD, r17
  out PORTD, r0

  ;; Setup stack ptr
  ldi r17, RAMEND >> 8
  out SPH, r17
  ldi r17, RAMEND & 255
  out SPL, r17

  ;; Setup TIMER1
  ;lds r17, PRR
  ;andi r17, 255 ^ (1 << PRTIM1)
  ;sts PRR, r17                    ; turn of power management bit on TIMER1

  ldi r17, (INTERRUPT_COUNT >> 8)
  sts OCR1AH, r17
  ldi r17, (INTERRUPT_COUNT & 0xff) ; compare to 1000 clocks (0.0625ms)
  sts OCR1AL, r17

  ldi r17, (1 << OCIE1A)
  sts TIMSK1, r17                 ; enable interrupt compare A 
  sts TCCR1C, r0
  sts TCCR1A, r0                  ; normal counting (0xffff is top, count up)
  ldi r17, (1 << CS10) | ( 1 << WGM12)   ; CTC OCR1A
  sts TCCR1B, r17                 ; prescale = 1 from clock source

  ;; Set up rs232 baud rate
  ;; (16MHz / (16 * 9600)) - 1 = 103 @ 16MHz = 9600 baud
  ldi r17, 0
  sts UBRR1H, r17
  ldi r17, 103
  sts UBRR1L, r17

  ;; Set up UART options
  ldi r17, (1 << UCSZ10) | (1 << UCSZ11)    ; sets up data as 8N1
  sts UCSR1C, r17
  ldi r17, (1 << TXEN1) | (1 << RXEN1)      ; enables send/receive
  sts UCSR1B, r17
  eor r17, r17
  sts UCSR1A, r17

  ;; Enable interrupts.
  sei

  ;rcall delay_1sec

main:
  ;; Turn on GREEN LED.
  cbi PORTD, 5

main_loop:
  ;; Poll uart to see if there is a data waiting.
  lds r21, UCSR1A
  sbrs r21, RXC1
  rjmp main_loop

  ;; Read from UART.
  lds r21, UDR1

  ;; Turn off GREEN LED.
  sbi PORTD, 5

  ;; Move Romi based on command.
  cpi r21, 'f'
  breq forward
  cpi r21, 'b'
  breq back
  cpi r21, 'l'
  breq rotate_left
  cpi r21, 'r'
  breq rotate_right
  cpi r21, 's'
  breq stop

  ;; Unknown command.
  ldi r17, '*'
  rjmp main

forward:
  rcall get_count
  ;sbi PORTB, MOTOR_LEFT_DIR
  ;sbi PORTB, MOTOR_RIGHT_DIR
  ;sbi PORTB, MOTOR_LEFT_SPEED
  ;sbi PORTB, MOTOR_RIGHT_SPEED
  ldi r17, (1 << MOTOR_LEFT_DIR) | (1 << MOTOR_RIGHT_DIR) | (1 << MOTOR_LEFT_SPEED) | (1 << MOTOR_RIGHT_SPEED)
  mov r5, r17
  rcall wait_count
  rjmp main

back:
  rcall get_count
  ;sbi PORTB, MOTOR_LEFT_DIR
  ;sbi PORTB, MOTOR_RIGHT_DIR
  ;sbi PORTB, MOTOR_LEFT_SPEED
  ;sbi PORTB, MOTOR_RIGHT_SPEED
  ldi r17, (1 << MOTOR_LEFT_SPEED) | (1 << MOTOR_RIGHT_SPEED)
  mov r5, r17
  rcall wait_count
  rjmp main

rotate_right:
  rcall get_count
  ;cbi PORTB, MOTOR_LEFT_DIR
  ;sbi PORTB, MOTOR_RIGHT_DIR
  ;sbi PORTB, MOTOR_LEFT_SPEED
  ;sbi PORTB, MOTOR_RIGHT_SPEED
  ldi r17, (1 << MOTOR_RIGHT_DIR) | (1 << MOTOR_LEFT_SPEED) | (1 << MOTOR_RIGHT_SPEED)
  mov r5, r17
  rcall wait_count
  rjmp main

rotate_left:
  rcall get_count
  ;sbi PORTB, MOTOR_LEFT_DIR
  ;cbi PORTB, MOTOR_RIGHT_DIR
  ;sbi PORTB, MOTOR_LEFT_SPEED
  ;sbi PORTB, MOTOR_RIGHT_SPEED
  ldi r17, (1 << MOTOR_LEFT_DIR) | (1 << MOTOR_LEFT_SPEED) | (1 << MOTOR_RIGHT_SPEED)
  mov r5, r17
  rcall wait_count
  rjmp main

stop:
  ;cbi PORTB, MOTOR_LEFT_SPEED
  ;cbi PORTB, MOTOR_RIGHT_SPEED
  ;cbi PORTB, MOTOR_LEFT_DIR
  ;cbi PORTB, MOTOR_RIGHT_DIR
  mov r5, r0

  ldi r17, '*'
  rjmp main

get_count:
  lds r21, UCSR1A
  sbrs r21, RXC1
  rjmp get_count

  ;; Read from UART.
  lds r21, UDR1
  ret

wait_count:
  mov r30, r0
  mov r31, r21
  clc
  ror r31
  ror r30
  ror r31
  ror r30
  ror r31
  ror r30
wait_count_next:
wait_count_off:
  sbi PORTC, 7
  in r17, PINB
  sbrs r17, 4
  rjmp wait_count_off
wait_count_on:
  cbi PORTC, 7
  in r17, PINB
  sbrc r17, 4
  rjmp wait_count_on
  ;dec r21
  sbiw r30, 1
  brne wait_count_next
  mov r5, r0

  ;; Write to UART to let host device know more data can be sent.
  ldi r17, '*'
  sts UDR1, r17
  ret

timer1_match_a_interrupt:
  ; Save status register.
  in r7, SREG

  inc r20
  cpi r20, 200
  brlo turn_off_motors

  out PORTB, r5
  ;sbi PORTC, 7
  rjmp exit_interrupt

turn_off_motors:
  out PORTB, r0
  ;cbi PORTC, 7

exit_interrupt:
  ; Restore status register.
  out SREG, r7
  reti

