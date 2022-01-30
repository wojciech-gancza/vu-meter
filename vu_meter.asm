;-------------------------------------------------------------------------------

.include			"m32adef.inc"			; ATMega32

;-------------------------------------------------------------------------------
; Register usage:
;	R0  - value to be displayed at left bar - cleared after displaying
;	R1  - value to be displayed at left as a dot - not cleared
;	R2  - value to be displayed at right bar - cleared after displaying
;	R3  - value to be displayed at right as a dot - not cleared
;	R4  - counter incremented as each 1ms timer tick, bits 0 and 1 used as diplay 
;		  marker selection what is currently displayed
;	R5  - decay counter counting down time to decrease dot value - left bar
;	R6  - decay counter counting down time to decrease dot value - right bar
;	R7  - low byte of left channel voltage
;	R8  - high byte of left channel voltage
;	R9  - low byte of right channel voltage
;	R10 - high byte of right channel voltage
;   ...
; 	R16 - commonly used as accumulator. For local use and passing parameters
;	R17 - temporary register - just to keep locally some values
;   ...
;   R30 - ZL - used as address register. To free local use
;   R31 - ZH - used as address register. To free local use
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
					jmp		adcReady			; ADC 
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

				; initialize analog to digitap converter - set ADMUX
				; REFS  = 01    - full voltage range (5v)
				; ALDAR = 0     - right aligned value
				; MUX   = 00000 - single ended ADC0
					ldi		r16, 0b01000000
					out		ADMUX, r16
				; setting ADCSRA
				; ADEN  = 1     - ADC converter enabled
				; ADSC  = 1     - start conversion
				; ADATE = 0     - auto trigger disabled
				; ADIF  = 0     - this is interupt flag - do not pay with it
				; ADIE  = 1     - ADC interupt enable
				; ADPS  = 110   - clock division factor = 64
					ldi		r16, 0b11001110
					out		ADCSRA, r16

				; main loop - reads interface and reacts on changes
				; all the important functionality is in inerupts
					sei
mainLoop:		 	rjmp	mainLoop		

;-------------------------------------------------------------------------------
; timer interupt - called each 1ms, handles display multiplexion and decay
; of dot display

.equ				DOT_DELAY = 200
.equ				DOT_DECAY = 3

timerTick1ms:		push	r16
					in		r16, SREG
					push	r16

				; set counter back to -125
					ldi		r16, -125
					out		TCNT2, r16

				; update state of the display
					push	r17
					push	zl
					push	zh

					rcall	clearBar

handleDisplay:	; R4: 	bit0: 0:Left,    1:Right
				;	 	bit1: 0:Dot+Bar, 1:Bar
					inc		r4
					sbrc	r4, 0
					rjmp	timerStep_1

					rcall	selectL

					sbrc	r4, 1
					rjmp	timerStep10

timerStep00:		mov		r16, r0
					eor		r0, r0
					rcall	showBar

timerStep10:		mov		r16, r1
					rcall	addDot

					rjmp	handleDisplayEnd

timerStep_1:		rcall	selectR
					
					sbrc	r4, 1
					rjmp	timerStep11

timerStep01:		mov		r16, r2
					eor		r2, r2
					rcall	showBar

timerStep11:		mov		r16, r3
					rcall	addDot

handleDisplayEnd:	nop

handleDotDecay:		ldi		r16, $03 ; mask for tic counter - to perform dot decay
					and		r16, r4	
					brne	handleDotDecayEnd

handleFirstDot:		and 	r1, r1
					breq	handleSecondDot

					dec		r5
					brne	handleSecondDot
					dec		r1
					ldi		r16, DOT_DECAY
					mov		r5, r16

handleSecondDot:	and 	r3, r3
					breq	handleDotDecayEnd

					dec		r6
					brne	handleDotDecayEnd
					dec		r3
					ldi		r16, DOT_DECAY
					mov		r6, r16

handleDotDecayEnd:	nop

timerEnd:		; additional tick handling can be placed here

endOfInterupt:		pop		zh
					pop		zl
					pop		r17

					pop		r16
					out		SREG, r16
					pop		r16
					reti

;-------------------------------------------------------------------------------
; ADC ready interupt handler

adcReady:			push	r16
					in		r16, SREG
					push	r16
					push	r17

					in		r16, ADMUX
					andi	r16, $01
					brne	adcRight

adcLeft:			in		r7, ADCL
					in		r8, ADCH

					ldi		r16, 0b01000001
					out		ADMUX, r16
										
					rjmp	adcNext

adcRight:			in		r9, ADCL
					in		r10, ADCH

					ldi		r16, 0b01000000
					out		ADMUX, r16

adcNext:			ldi		r17, 0b11001110
					out		ADCSRA, r17

					andi	r16, 0b00000001
					brne	adcEnd

				; use value - both channel were read

					mov		r16, r7
					mov		r17, r8
					rcall	voltageToLedsCnt
					rcall	setLeftLeds

					mov		r16, r9
					mov		r17, r10
					rcall	voltageToLedsCnt
					rcall	setRightLeds
						
adcEnd:				pop		r17
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
; setting value to display - for left and right led bar. contain logic of 
; setting dot indicating peak values

setLeftLeds:	; r16 - value
					cp		r16, r0
					brlt	notSet
					mov		r0, r16
					cp		r16, r1
					brlt	notSet
					mov     r1, r16
					ldi		r16, DOT_DELAY
					mov		r5, r16
notSet:				ret

setRightLeds:	; r16 - value
					cp		r16, r2
					brlt	notSet
					mov		r2, r16
					cp		r16, r3
					brlt	notSet
					mov     r3, r16
					ldi		r16, DOT_DELAY
					mov		r6, r16
					ret

;-------------------------------------------------------------------------------
; Conversion from value to count of lighted diodes. This is inlined to minimise 
; conversion time. 

.equ				LEVEL_20 = 514
.equ				LEVEL_19 = 408
.equ				LEVEL_18 = 324
.equ				LEVEL_17 = 257
.equ				LEVEL_16 = 204
.equ				LEVEL_15 = 162
.equ				LEVEL_14 = 129
.equ				LEVEL_13 = 102
.equ				LEVEL_12 =  81
.equ				LEVEL_11 =  64
.equ				LEVEL_10 =  51
.equ				LEVEL_09 =  40
.equ				LEVEL_08 =  32
.equ				LEVEL_07 =  25
.equ				LEVEL_06 =  20
.equ				LEVEL_05 =  16
.equ				LEVEL_04 =  12
.equ				LEVEL_03 =  10
.equ				LEVEL_02 =   8
.equ				LEVEL_01 =   6

voltageToLedsCnt:	; Input: R17:R16 - value to convert
					; Output: r16 - count of leds to display

				; compare with 16
					cpi		r17, high(LEVEL_16)
					brlo	values_00_15
					brne	values_16_20
					cpi		r16, low(LEVEL_16)
					brlo	values_00_15		

values_16_20:	; compare with 20
					cpi		r17, high(LEVEL_20)
					brlo	values_16_19
					brne	value_20
					cpi		r16, low(LEVEL_20)
					brlo	values_16_19
					
value_20:			ldi		r16, 20
					ret

values_16_19:	; compare with 18
					cpi		r17, high(LEVEL_18)
					brlo	values_16_17
					brne	values_18_19
					cpi		r16, low(LEVEL_18)
					brlo	values_16_17

values_18_19:	; compare with 19
					cpi		r17, high(LEVEL_19)
					brlo	value_18
					brne	value_19
					cpi		r16, low(LEVEL_19)
					brlo	value_18	
					
value_19:			ldi		r16, 19
					ret

value_18:			ldi		r16, 18
					ret

values_16_17:	; compare with 17
					cpi		r17, high(LEVEL_17)
					brlo	value_16
					brne	value_17
					cpi		r16, low(LEVEL_17)
					brlo	value_16

value_17:			ldi		r16, 17
					ret
					
value_16:			ldi		r16, 16
					ret

values_00_15:	; compare with 08
					cpi		r17, high(LEVEL_08)
					brlo	values_00_07
					brne	values_08_15
					cpi		r16, low(LEVEL_08)
					brlo	values_00_07		

values_08_15:	; compare with 12
					cpi		r17, high(LEVEL_12)
					brlo	values_08_11
					brne	values_12_15
					cpi		r16, low(LEVEL_12)
					brlo	values_08_11		
		
values_12_15:	; compare with 14
					cpi		r17, high(LEVEL_14)
					brlo	values_12_13
					brne	values_14_15
					cpi		r16, low(LEVEL_14)
					brlo	values_12_13		
		
values_14_15:	; compare with 15
					cpi		r17, high(LEVEL_15)
					brlo	value_14
					brne	value_15
					cpi		r16, low(LEVEL_15)
					brlo	value_14		
			
value_15:			ldi		r16, 15
					ret	

value_14:			ldi		r16, 14
					ret	

values_12_13:	; compare with 13
					cpi		r17, high(LEVEL_13)
					brlo	value_12
					brne	value_13
					cpi		r16, low(LEVEL_13)
					brlo	value_12	
					
value_13:			ldi		r16, 13
					ret	

value_12:			ldi		r16, 12
					ret	

values_08_11:	; compare with 10
					cpi		r17, high(LEVEL_10)
					brlo	values_08_09
					brne	values_10_11
					cpi		r16, low(LEVEL_10)
					brlo	values_08_09
					
values_10_11:	; compare with 11
					cpi		r17, high(LEVEL_11)
					brlo	value_10
					brne	value_11
					cpi		r16, low(LEVEL_11)
					brlo	value_10
						
value_11:			ldi		r16, 11
					ret

value_10:			ldi		r16, 10
					ret

values_08_09:	; compare with 9
					cpi		r17, high(LEVEL_09)
					brlo	value_08
					brne	value_09
					cpi		r16, low(LEVEL_09)
					brlo	value_08
					
value_09:			ldi		r16, 9
					ret

value_08:			ldi		r16, 8
					ret

values_00_07:	; compare with 04
					cpi		r17, high(LEVEL_04)
					brlo	values_00_03
					brne	values_04_07
					cpi		r16, low(LEVEL_04)
					brlo	values_00_03		
	
values_04_07:	; compare with 06
					cpi		r17, high(LEVEL_06)
					brlo	values_04_05
					brne	values_06_07
					cpi		r16, low(LEVEL_06)
					brlo	values_04_05
					
values_06_07:	; compare with 05
					cpi		r17, high(LEVEL_07)
					brlo	value_06
					brne	value_07
					cpi		r16, low(LEVEL_07)
					brlo	value_06
					
value_07:			ldi		r16, 7
					ret

value_06:			ldi		r16, 6
					ret

values_04_05:	; compare with 05
					cpi		r17, high(LEVEL_05)
					brlo	value_04
					brne	value_05
					cpi		r16, low(LEVEL_05)
					brlo	value_04
					
value_05:			ldi		r16, 5
					ret

value_04:			ldi		r16, 4
					ret

values_00_03:	; compare with 02
					cpi		r17, high(LEVEL_02)
					brlo	values_00_01
					brne	values_02_03
					cpi		r16, low(LEVEL_02)
					brlo	values_00_01		
	
values_02_03:	; compare with 01
					cpi		r17, high(LEVEL_03)
					brlo	value_02
					brne	value_03
					cpi		r16, low(LEVEL_03)
					brlo	value_02

value_03:			ldi		r16, 3
					ret

value_02:			ldi		r16, 2
					ret

values_00_01:	; compare with 01
					cpi		r17, high(LEVEL_01)
					brlo	value_00
					brne	value_01
					cpi		r16, low(LEVEL_01)
					brlo	value_00
					
value_01:			ldi		r16, 1
					ret

value_00:			ldi		r16, 0
					ret

;-------------------------------------------------------------------------------
