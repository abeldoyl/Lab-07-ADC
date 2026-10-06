    ; Abel Doyle
    ; RCET3373
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
count    EQU 0x20         ;use data memory address 0x20 as an 8-bit loop counter  
; Reset Vector at 0000h. Execution starts here after reset.
PSECT resetVect,class=CODE,delta=2
ResetVector: 
    goto Setup

; Main code section starts at 0008h. User code goes here.
PSECT code,class=CODE,delta=2

Setup:
    ; add device setup here
    ; Bank 0
    BCF 0x03,6      ;Set Bank 0
    BCF 0x03,5      ;Set Bank 0
    CLRF PORTA      ;Clearing PORTA on reset
    CLRF PORTB      ;Clearing PORTB on reset
    CLRF PORTC      ;Clearing PORTC on reset

    ; Bank 1
    BCF 0x03,6      ;Set Bank 1
    BSF 0x03,5      ;Set Bank 1
    CLRF INTCON     ;Set INTCON low to remove interrupt flags
    MOVLW 0x61
    MOVWF OSCCON    ;Internal oscillator at 4 MHz (IRCF = 110)
    MOVLW 0x01
    MOVWF TRISA     ;RA0 input (pot), RA1 output (diagnostic), rest outputs
    CLRF TRISB      ;Making PORTB outputs (ADRESL)
    CLRF TRISC      ;Making PORTC outputs (ADRESH)
    MOVLW 0x80
    MOVWF ADCON1    ;ADFM = 1 (right justified), VCFG = 00 (VDD/VSS references)

    ;Bank 3
    BSF 0x03,6      ;Set Bank 3
    BSF 0x03,5      ;Set Bank 3
    MOVLW 0x01
    MOVWF ANSEL     ;RA0 (AN0) analog, rest of PORTA digital
    CLRF ANSELH     ;Making PORTB digital I/O

    ; Bank 0
    BCF 0x03,6      ;Sets Bank 0
    BCF 0x03,5      ;Sets Bank 0
    MOVLW 0x41
    MOVWF ADCON0    ;ADCS = 01 (FOSC/8, TAD = 2 us), CHS = AN0, ADC on
    goto Main

Main:
    ; main code goes here
    NOP             ;Acquisition delay
    NOP
    NOP
    NOP
    NOP
    BSF PORTA,1     ;Diagnostic HIGH
    BSF ADCON0,1    ;Start conversion (GO)
    BTFSC ADCON0,1  ;Is conversion done?
    goto $-1        ;If not, check again
    BCF PORTA,1     ;Diagnostic LOW

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
    goto Main
End