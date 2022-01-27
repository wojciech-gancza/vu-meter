;-------------------------------------------------------------------------------

.include			"m32adef.inc"			; ATMega32

;-------------------------------------------------------------------------------
					.dseg	
					.equ 	os_stack_size 	= 128 	; size of machine stack

os_system_stack:	.byte	os_stack_size

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
					.cseg
					.org 	0

				; interupt vector 
ivect:				jmp 	initOS				; RESET
					jmp		empty				; INT0
					jmp		empty				; INT1
					jmp		empty				; INT2
					jmp		empty				; TIMER2 COMP
					jmp		timerTick1ms		; TIMER2 OVF
					jmp		empty				; TIMER1 CAPT
					jmp		empty				; TIMER1 COMPA
					jmp		empty				; TIMER1 COMPB
					jmp		empty				; TIMER1 OVF
					jmp		empty				; TIMER0 COMP
					jmp		empty				; TIMER0 OVF
					jmp		empty				; SPI, STC 
					jmp		empty				; USART, RXC
					jmp		empty				; USART, UDRE 
					jmp		empty				; USART, TXC
					jmp		empty				; ADC 
					jmp		empty				; EE_RDY
					jmp		empty				; ANA_COMP
					jmp		empty				; TWI
					jmp		empty			    ; SPM_RDY

empty:				reti

;-------------------------------------------------------------------------------

				; main excution flow
initOS:				cli
				; setting stack pointer to the end of the stack
					ldi		zh, high(os_system_stack+os_stack_size-1)
					ldi		zl, low(os_system_stack+os_stack_size-1)
					out		SPH, zh
					out		SPL, zl
					
					
				; set ports direction
				; output: (inactive: high)
				; 20 lines: PD0-7, PC0-7, PA4-7 - lines
				; 2 rows:	PB6-7
					ldi		r16, 0b11111111
					out		PORTC, r16
					out		PORTD, r16
					out		DDRC, r16
					out		DDRD, r16
					ldi		r16, 0b11110000
					out		PORTA, r16
					out		DDRA, r16
					ldi		r16, 0b11000000
					out		PORTB, r16
					out		DDRB, r16

				; set TIMER2 as main clock source 1ms at 8MHz:
				; FOC2 = 0   - default
				; WGM2 = 00  - normal
				; COM2 = 00  - OC2 disconnected
				; CS2  = 100 - /64
					ldi		r16, 0b00000100
					out		TCCR2, r16
				; count 125 tick until interupt
					ldi		r16, -125
					out		TCNT2, r16
				; enable timer2 overflow interupt
				; OCIE2 = 0
				; TOIE2 = 1
					ldi		r16, 0b01000000
					out 	TIMSK, r16

				; initialize display 
					ldi		r16, 0
					mov		r0, r16	; left bar value on bits 0:4
					mov		r1, r16 ; left dot value on bits 0:4
					mov		r2, r16 ; right bar value on bits 0:4
					mov		r3, r16 ; right dot value on bits 0:4
					mov		r4, r16	; display step counter
					rcall   displayOff
					rcall	clearBar

				; test code 
					ldi		r16, 9
					mov		r0, r16
					ldi		r16, 11
					mov		r1, r16
					ldi		r16, 17
					mov		r2, r16
					ldi		r16, 8
					mov		r3, r16

				; main loop - reads interface and reacts on changes
				; all the important functionality is in inerupts
					sei
mainLoop:		 	rjmp	mainLoop		

;-------------------------------------------------------------------------------

timerTick1ms:		push	r16
					in		r16, SREG
					push	r16

				; set counter back to -125
					ldi		r16, -125
					out		TCNT2, r16

					push	r17
					push	zl
					push	zh

					rcall	clearBar

				; R4: 	bit0: 0:Left,    1:Right
				;	 	bit1: 0:Dot+Bar, 1:Bar
					inc		r4
					sbrc	r4, 0
					rjmp	timerStep_1

					rcall	selectL

					sbrc	r4, 1
					rjmp	timerStep10

timerStep00:		mov		r16, r0
					rcall	showBar

timerStep10:		mov		r16, r1
					rcall	addDot

					rjmp	timerEnd

timerStep_1:		rcall	selectR
					
					sbrc	r4, 1
					rjmp	timerStep11

timerStep01:		mov		r16, r2
					rcall	showBar

timerStep11:		mov		r16, r3
					rcall	addDot

timerEnd:			pop		zh
					pop		zl
					pop		r17

					pop		r16
					out		SREG, r16
					pop		r16
					reti

;-------------------------------------------------------------------------------

; display procedures setting state of led diodes in VU led bars.

selectL:		; modify R16
					in		r16, PORTB
					ori		r16, 0b11000000
					andi	r16, 0b10111111
					out		PORTB, r16
					ret

selectR:		; modify R16
					in		r16, PORTB
					ori		r16, 0b11000000
					andi	r16, 0b01111111
					out		PORTB, r16
					ret

displayOff:		; modify R16
					in		r16, PORTB
					ori		r16, 0b11000000
					out		PORTB, r16
					ret

clearBar:		; modify R16
					ldi		r16, 0b11111111
					out		PORTD, r16
					out		PORTC, r16
					in		r16, PORTA
					andi	r16, 0b00001111
					ori		r16, 0b11110000
					out		PORTA, r16
					ret


showBar:		; R16 - number of dots
				; modify ZL, ZH

					mov		zl, r16
					add		r16, r16
					add		r16, zl
					ldi		zl, low(2*barValues)
					ldi		zh, high(2*barValues)
					add		zl, r16
					ldi 	r16, 0
					adc		zh, r16

					lpm		r16, z+
					out		PORTD, r16

					lpm		r16, z+
					out		PORTC, r16

					lpm		r16, z
					in		zl, PORTA
					andi	zl, $0f
					or		r16, zl
					out		PORTA, r16
					ret

addDot:			; R16 - dot position
				; modify R17, ZL, ZH

					mov		zl, r16
					add		r16, r16
					add		r16, zl
					ldi		zl, low(2*dotValues)
					ldi		zh, high(2*dotValues)
					add		zl, r16
					ldi 	r16, 0
					adc		zh, r16

					in		r17, PORTD
					lpm		r16, z+
					and		r16, r17
					out		PORTD, r16

					in		r17, PORTC
					lpm		r16, z+
					and 	r16, r17
					out		PORTC, r16

					in		r17, PORTA
					lpm		r16, z
					and		r16, r17
					out		PORTA, r16
					ret

barValues:			.db		0b11111111, 0b11111111, 0b11110000,	\
					 		0b11111111, 0b11111111, 0b11100000,	\
							0b11111111, 0b11111111, 0b11000000,	\
							0b11111111, 0b11111111, 0b10000000,	\
							0b11111111, 0b11111111, 0b00000000,	\
							0b11111111, 0b01111111, 0b00000000, \
							0b11111111, 0b00111111, 0b00000000, \
							0b11111111, 0b00011111, 0b00000000, \
							0b11111111, 0b00001111, 0b00000000, \
							0b11111111, 0b00000111, 0b00000000, \
							0b11111111, 0b00000011, 0b00000000, \
							0b11111111, 0b00000001, 0b00000000, \
							0b11111111, 0b00000000, 0b00000000, \
							0b01111111, 0b00000000, 0b00000000, \
							0b00111111, 0b00000000, 0b00000000, \
							0b00011111, 0b00000000, 0b00000000, \
							0b00001111, 0b00000000, 0b00000000, \
							0b00000111, 0b00000000, 0b00000000, \
							0b00000011, 0b00000000, 0b00000000, \
							0b00000001, 0b00000000, 0b00000000, \
							0b00000000, 0b00000000, 0b00000000, \
							$00 ; align to full bytes count

dotValues:			.db		0b11111111, 0b11111111, 0b11110000,	\
					 		0b11111111, 0b11111111, 0b11100000,	\
							0b11111111, 0b11111111, 0b11010000,	\
							0b11111111, 0b11111111, 0b10110000,	\
							0b11111111, 0b11111111, 0b01110000,	\
							0b11111111, 0b01111111, 0b11110000, \
							0b11111111, 0b10111111, 0b11110000, \
							0b11111111, 0b11011111, 0b11110000, \
							0b11111111, 0b11101111, 0b11110000, \
							0b11111111, 0b11110111, 0b11110000, \
							0b11111111, 0b11111011, 0b11110000, \
							0b11111111, 0b11111101, 0b11110000, \
							0b11111111, 0b11111110, 0b11110000, \
							0b01111111, 0b11111111, 0b11110000, \
							0b10111111, 0b11111111, 0b11110000, \
							0b11011111, 0b11111111, 0b11110000, \
							0b11101111, 0b11111111, 0b11110000, \
							0b11110111, 0b11111111, 0b11110000, \
							0b11111011, 0b11111111, 0b11110000, \
							0b11111101, 0b11111111, 0b11110000, \
							0b11111110, 0b11111111, 0b11110000, \
							$00 ; align to full bytes count

;-------------------------------------------------------------------------------
