    ; Abel Doyle
    ; RCET3375
    ; Lab7-2ADC
    ; https://github.com/abeldoyl/Lab-07-ADC/tree/main/Lab7-2ADC.X

; PIC16F883 Configuration Bit Settings

; Assembly source line config statements

; CONFIG1
  CONFIG  FOSC = XT             ; Oscillator Selection bits (XT oscillator: Crystal/resonator on RA6/OSC2/CLKOUT and RA7/OSC1/CLKIN)
  CONFIG  WDTE = OFF            ; Watchdog Timer Enable bit (WDT disabled and can be enabled by SWDTEN bit of the WDTCON register)
  CONFIG  PWRTE = OFF           ; Power-up Timer Enable bit (PWRT disabled)
  CONFIG  MCLRE = ON            ; RE3/MCLR pin function select bit (RE3/MCLR pin function is MCLR)
  CONFIG  CP = OFF              ; Code Protection bit (Program memory code protection is disabled)
  CONFIG  CPD = OFF             ; Data Code Protection bit (Data memory code protection is disabled)
  CONFIG  BOREN = OFF           ; Brown Out Reset Selection bits (BOR disabled)
  CONFIG  IESO = OFF            ; Internal External Switchover bit (Internal/External Switchover mode is disabled)
  CONFIG  FCMEN = OFF           ; Fail-Safe Clock Monitor Enabled bit (Fail-Safe Clock Monitor is disabled)
  CONFIG  LVP = OFF             ; Low Voltage Programming Enable bit (RB3 pin has digital I/O, HV on MCLR must be used for programming)

; CONFIG2
  CONFIG  BOR4V = BOR40V        ; Brown-out Reset Selection bit (Brown-out Reset set to 4.0V)
  CONFIG  WRT = OFF             ; Flash Program Memory Self Write Enable bits (Write protection off)

; config statements should precede project file includes.
#include <xc.inc>
; ---------------- Constants ----------------
; TRIM = measured loop/reload overhead in us. Start at 0, scope RA1,
; then set TRIM to how many us too long the pulse is.
TRIM        EQU 0
PW_START    EQU (500 - TRIM)            ; pulse for index 0 (trimmed)
LOW_BASE    EQU (45536 + 2*TRIM)        ; 65536 - 20000, plus trim
 
; ---------------- Variables (Bank 0) ----------------
ADC_L       EQU 0x20
ADC_H       EQU 0x21
PW_L        EQU 0x22        ;running pulse width (us)
PW_H        EQU 0x23
HI_L        EQU 0x24        ;Timer1 preload for the HIGH phase
HI_H        EQU 0x25
LO_L        EQU 0x26        ;Timer1 preload for the LOW phase
LO_H        EQU 0x27
 
PSECT resetVect,class=CODE,delta=2
ResetVector:
    goto Setup
 
PSECT code,class=CODE,delta=2
 
Setup:
    ; Bank 0: clear outputs and set up Timer1
    ; (STATUS bit 6 = RP1, bit 5 = RP0: 00 = Bank 0, 01 = Bank 1, 11 = Bank 3)
    BCF 0x03,6
    BCF 0x03,5
    CLRF INTCON             ;no interrupts used; all enables off
    CLRF PORTA              ;RA1 (servo) starts LOW
    CLRF PORTB
    CLRF PORTC
 
    ; Initial preloads = index 0 values, so the first frame is a valid
    ; 500 us pulse even before the first ADC reading.
    ; HIGH preload = 65536 - PW_START
    ; LOW  preload = LOW_BASE + PW_START
    MOVLW ((65536 - PW_START) & 0xFF)
    MOVWF HI_L
    MOVLW (((65536 - PW_START) >> 8) & 0xFF)
    MOVWF HI_H
    MOVLW ((LOW_BASE + PW_START) & 0xFF)
    MOVWF LO_L
    MOVLW (((LOW_BASE + PW_START) >> 8) & 0xFF)
    MOVWF LO_H
 
    CLRF T1CON              ;Fosc/4, 1:1, Timer1 off
    MOVLW 0xFF
    MOVWF TMR1H
    MOVLW 0xF0
    MOVWF TMR1L             ;first overflow almost immediately
    BCF PIR1,0              ;clear TMR1IF (polled, never enabled as interrupt)
 
    ; Bank 1
    BCF 0x03,6
    BSF 0x03,5
    MOVLW 0x01
    MOVWF TRISA             ;RA0 = pot input, RA1 = servo output
    CLRF TRISB
    CLRF TRISC
    MOVLW 0x80
    MOVWF ADCON1            ;right justified, VDD/VSS refs
 
    ; Bank 3
    BSF 0x03,6
    BSF 0x03,5
    MOVLW 0x01
    MOVWF ANSEL             ;AN0 analog only
    CLRF ANSELH
 
    ; Bank 0
    BCF 0x03,6
    BCF 0x03,5
    MOVLW 0x41
    MOVWF ADCON0            ;Fosc/8, AN0, ADC on
    BSF T1CON,0             ;Timer1 on
    goto Main
 
Main:
    ;==== HIGH phase: start the servo pulse ====
    BTFSS PIR1,0            ;is TMR1IF set? (Timer1 overflowed = frame boundary)
    goto $-1                ;no: keep waiting (3-cycle loop, ~3 us edge jitter)
    BSF PORTA,1             ;servo pulse HIGH (edge first, for consistent timing)
    MOVF HI_H,W
    MOVWF TMR1H             ;write high byte of the HIGH preload
    MOVF HI_L,W
    MOVWF TMR1L             ;write low byte (this also loads the 16-bit value)
    BCF PIR1,0              ;clear TMR1IF so we can detect the next overflow
 
    ;==== Wait for the pulse width to elapse, then end the pulse ====
    BTFSS PIR1,0            ;overflow = Timer1 counted P us
    goto $-1
    BCF PORTA,1             ;servo pulse LOW
    MOVF LO_H,W
    MOVWF TMR1H
    MOVF LO_L,W
    MOVWF TMR1L             ;now Timer1 times the rest of the frame (20000 - P us)
    BCF PIR1,0
 
    ;==== LOW phase: read the pot and compute the next frame's preloads ====
    ; The timer is counting in the background, so none of this affects timing.
    NOP                     ;acquisition delay so the ADC sample cap can charge
    NOP
    NOP
    NOP
    NOP
    BSF ADCON0,1            ;set GO/DONE: start conversion
    BTFSC ADCON0,1          ;GO/DONE clears itself when the conversion is done
    goto $-1
 
    MOVF ADRESH,W           ;ADRESH is in Bank 0
    MOVWF ADC_H             ;save the 2 MSBs of the 10-bit result
    BCF 0x03,6              ;Bank 1 (ADRESL lives here)
    BSF 0x03,5
    MOVF ADRESL,W
    BCF 0x03,6              ;back to Bank 0 before touching variables
    BCF 0x03,5
    MOVWF ADC_L             ;save the 8 LSBs; ADC_H:ADC_L = 0..1023
 
    MOVF ADRESH,W   ;ADRESH is in Bank 0
    MOVWF PORTC     ;Store MSBs in PORTC

    ; Bank 1
    BCF 0x03,6      ;Set Bank 1
    BSF 0x03,5      ;Set Bank 1
    MOVF ADRESL,W   ;ADRESL is in Bank 1

    ; Bank 0
    BCF 0x03,6      ;Set Bank 0
    BCF 0x03,5      ;Set Bank 0
    MOVWF PORTB     ;Store LSBs in PORTB
    
    ;---- ADC -> pulse width ----
    ; index n = ADC / 49 using repeated subtraction. Each time 49 can be
    ; subtracted, n goes up by one and the pulse grows by 100 us.
    ; ADC 0..48 -> n=0 (500 us) ... ADC 980..1023 -> n=20 (2500 us).
    MOVLW (PW_START & 0xFF)
    MOVWF PW_L
    MOVLW ((PW_START >> 8) & 0xFF)
    MOVWF PW_H              ;PW starts at the index-0 pulse width
 
DivLoop:
    ; Is ADC (16-bit) >= 49 ?
    MOVF ADC_H,F            ;sets Z if ADC_H = 0 (MOVF to itself just tests it)
    BTFSS STATUS,2          ;Z set? then ADC < 256, need to check the low byte
    goto DoSub              ;ADC_H nonzero: ADC >= 256, definitely >= 49
    MOVLW 49
    SUBWF ADC_L,W           ;W = ADC_L - 49; carry = 1 if ADC_L >= 49 (no borrow)
    BTFSS STATUS,0
    goto DivDone            ;carry clear: ADC < 49, division finished
DoSub:
    MOVLW 49
    SUBWF ADC_L,F           ;ADC_L = ADC_L - 49
    BTFSS STATUS,0          ;carry clear means the low byte borrowed
    DECF ADC_H,F            ;pass the borrow to the high byte
    MOVLW 100
    ADDWF PW_L,F            ;PW_L = PW_L + 100
    BTFSC STATUS,0          ;carry set means the low byte overflowed
    INCF PW_H,F             ;pass the carry to the high byte
    goto DivLoop            ;repeat until ADC < 49 (at most 20 times)
 
DivDone:
    ;---- pulse width -> Timer1 preloads ----
    ; HIGH preload = 65536 - PW  (two's complement of PW)
    COMF PW_H,W             ;invert the high byte
    MOVWF HI_H
    COMF PW_L,W             ;invert the low byte
    MOVWF HI_L
    INCF HI_L,F             ;+1 completes the two's complement
    BTFSC STATUS,2          ;low byte wrapped from 0xFF to 0x00?
    INCF HI_H,F             ;then carry into the high byte
 
    ; LOW preload = LOW_BASE + PW  (so LOW time = 20000 - PW)
    MOVLW (LOW_BASE & 0xFF)
    ADDWF PW_L,W            ;W = PW_L + low byte of LOW_BASE
    MOVWF LO_L
    MOVLW ((LOW_BASE >> 8) & 0xFF)
    BTFSC STATUS,0          ;carry out of the low-byte add?
    ADDLW 1                 ;then add it into the high byte constant
    ADDWF PW_H,W            ;W = PW_H + high byte of LOW_BASE (+ carry)
    MOVWF LO_H
 
    goto Main               ;back to wait for the next frame boundary
                            ;(the new HI/LO values are used on the next frame)
 
End