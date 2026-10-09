; Abel Doyle
    ; RCET3375
    ; Lab7-4ADC
    ; https://github.com/abeldoyl/Lab-07-ADC/tree/main/Lab7-4ADC.X
 
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
 
; ---- Bank 0 variables ----
 busy        EQU 0x20   ; 1 while the servo pulse is HIGH
 ccp_next_l  EQU 0x21   ; compare value returned by MapAdcToCcp (low)
 ccp_next_h  EQU 0x22   ; compare value returned by MapAdcToCcp (high)
 adc_l       EQU 0x23   ; right-justified 10-bit ADC result (low)  - also module work reg
 adc_h       EQU 0x24   ; right-justified 10-bit ADC result (high) - also module work reg
                        ; 0x25 is reserved by the supplied mapping module - do not use
 ccp_save_l  EQU 0x26
 ccp_save_h  EQU 0x27
 adc_done    EQU 0x28   ; moved from 0x21

GLOBAL  ccp_next_l, ccp_next_h, adc_l, adc_h
EXTRN   MapAdcToCcp
 
; ---- common RAM (0x70-0x7F), reachable from any bank without BANKSEL ----
 W_TEMP      EQU 0x70   ; saved W      - ISR context
 STATUS_TEMP EQU 0x71   ; saved STATUS - "
 PCLATH_TEMP EQU 0x72   ; saved PCLATH - "
 
PSECT resetVect,class=CODE,delta=2
ResetVector:
    goto Setup
 
; INTERRUPT VECTOR (address 0x04). All interrupts land here.
; The context save is done right in the vector, before any GOTO, because GOTO
; builds its target address from PCLATH. Main may have just done a PAGESEL to
; the lookup module's page, so PCLATH is saved and cleared first so that
; the jump to ISRHandler goes to page 0.
PSECT isrVect,class=CODE,delta=2
InterruptVector:
    goto ISRHandler
 
PSECT code,class=CODE,delta=2
 
; SETUP - runs once after reset. Interrupts stay off until the very end.
Setup:
    BANKSEL PORTA
    CLRF PORTA
    CLRF PORTB
    CLRF PORTC              ; RC2 (servo) starts LOW
    CLRF PIR1               ; clear stale TMR1IF / CCP1IF flags
    CLRF INTCON             ; all interrupts off while configuring
    CLRF busy               ; no pulse in progress
    CLRF adc_done           ; no command prepared yet
 
    BANKSEL TRISA
    MOVLW 0x01
    MOVWF TRISA             ; RA0/AN0 = input (potentiometer)
    CLRF TRISB
    CLRF TRISC              ; PORTC all outputs; RC2 = servo signal
    BANKSEL ADCON1
    MOVLW 0x80
    MOVWF ADCON1            ; ADFM = 1 -> RIGHT justified
                            ; ADRESH = bits 9:8, ADRESL = bits 7:0
                            ; VCFG1:VCFG0 = 00 -> references VDD/VSS
    BANKSEL PIE1
    MOVLW 0x05
    MOVWF PIE1              ; bit2 CCP1IE = 1 (end of pulse), bit0 TMR1IE = 1 (frame start)
 
    BANKSEL ANSEL
    MOVLW 0x01
    MOVWF ANSEL             ; AN0 analog, other pins digital
    BANKSEL ANSELH
    CLRF ANSELH             ; AN8-AN13 digital
 
    BANKSEL ADCON0
    MOVLW 0x41
    MOVWF ADCON0            ; ADCS = 01 (FOSC/8), CHS = 0000 (AN0), ADON = 1
                            ; ADC stays enabled between conversions
 
    BANKSEL T1CON
    CLRF T1CON              ; TMR1CS = 0 (FOSC/4 = 1 us tick), prescaler 1:1, Timer1 OFF
    MOVLW 0x0A
    MOVWF CCP1CON           ; CCP1M = 1010: Compare, software interrupt on match,
                            ; CCP1 pin unaffected (RC2 is controlled in software)
    MOVLW 0xFF
    MOVWF TMR1H
    MOVLW 0xF0
    MOVWF TMR1L             ; preload near rollover so the first frame starts right away
 
    CALL AcquireAndMap      ; read the pot once and load the first compare value
 
    BSF T1CON,0             ; TMR1ON = 1 -> Timer1 starts counting
    BSF INTCON,6            ; PEIE = 1 (peripheral interrupts: Timer1 and CCP1)
    BSF INTCON,7            ; GIE  = 1 (last, once everything is ready)
 
; MAIN - the pulse timing is done entirely by the ISR, so Main only
; prepares the NEXT frame's command, once per frame, during the idle time
; after the pulse has ended. Anything else could be added here, since it
; could be interrupted at any point without harming the servo signal.
Main:
    MOVF busy,F             ; test busy (sets Z if busy = 0)
    BTFSS STATUS,2          ; Z set -> pulse finished
    goto Main               ; pulse still active: don't touch the ADC/compare value
    MOVF adc_done,F         ; test adc_done (sets Z if not yet prepared)
    BTFSS STATUS,2          ; Z set -> next command NOT prepared yet
    goto Main               ; already prepared this frame: idle until next overflow
    CALL AcquireAndMap      ; read ADC, map to compare value, save for next frame
    goto Main
 
; ISR HANDLER - Saves W, STATUS and PCLATH registers.
; Two possible sources, never both at the same time in normal operation:
;   TMR1IF -> 20 ms frame boundary: pulse goes HIGH
;   CCP1IF -> Timer1 matched the compare value: pulse goes LOW
ISRHandler:
    MOVWF W_TEMP            ; save W (no flags affected)
    SWAPF STATUS,W          ; SWAPF doesn't change STATUS bits, unlike MOVF
    MOVWF STATUS_TEMP       ; save STATUS (nibble-swapped)
    MOVF PCLATH,W
    MOVWF PCLATH_TEMP       ; save PCLATH
    CLRF PCLATH             ; force page 0 so the GOTO below lands correctly
    BANKSEL PIR1            ; flags live in Bank 0
    BTFSC PIR1,0            ; TMR1IF set?
    goto T1Overflow
    BTFSC PIR1,2            ; CCP1IF set?
    goto CcpMatch
    goto ISRExit            ; neither (shouldn't happen) - just leave
 
; TIMER1 OVERFLOW - starts a new 20 ms frame.
; Reloading with 0xB1E0 (45536) leaves exactly 20000 counts of 1 us until the
; next overflow. The servo output goes HIGH, and the CCP register is loaded
; with the deadline calculated during the previous frame.
T1Overflow:
    MOVLW 0xB1
    MOVWF TMR1H             ; reload high byte  (0xB1E0 = 45536)
    MOVLW 0xE0
    MOVWF TMR1L             ; reload low byte (also latches the 16-bit value)
    BCF PIR1,0              ; clear TMR1IF
    BSF PORTC,2             ; servo output HIGH (pulse starts)
    MOVF ccp_save_l,W
    MOVWF CCPR1L            ; load compare value (low)  - safe: no pulse is active
    MOVF ccp_save_h,W
    MOVWF CCPR1H            ; load compare value (high)
    CLRF adc_done           ; allow Main to prepare the next frame's command
    MOVLW 1
    MOVWF busy              ; pulse is now active
    goto ISRExit
 
; CCP1 COMPARE MATCH - Timer1 reached the saved deadline = end of the pulse.
; This is the only interrupt at the end of the pulse; no software delay needed.
CcpMatch:
    BCF PIR1,2              ; clear CCP1IF
    BCF PORTC,2             ; servo output LOW (pulse ends)
    CLRF busy               ; pulse finished -> Main may prepare the next command
    goto ISRExit
 
; CONTEXT RESTORE (datasheet SWAPF method) - reverse of the vector's saves
ISRExit:
    MOVF PCLATH_TEMP,W
    MOVWF PCLATH            ; restore PCLATH
    SWAPF STATUS_TEMP,W     ; un-swap STATUS nibbles into W
    MOVWF STATUS            ; restore STATUS (also restores the original bank)
    SWAPF W_TEMP,F
    SWAPF W_TEMP,W          ; restore W without disturbing STATUS
    RETFIE                  ; return and set GIE again
 
; ACQUIRE AND MAP - one ADC read -> 6-bit index -> compare value for next frame.
; Called from Setup (first frame) and from Main (every later frame).
; Assumes Bank 0 on entry and leaves in Bank 0.
AcquireAndMap:
    NOP                     ; acquisition delay so the sample capacitor can charge
    NOP
    NOP
    NOP
    NOP
    BSF ADCON0,1            ; GO/DONE = 1 -> start conversion
WaitAdc:
    BTFSC ADCON0,1          ; GO/DONE clears itself when the conversion finishes
    goto WaitAdc
 
    MOVF ADRESH,W           ; Bank 0: ADC bits 9:8 (upper bits read 0)
    MOVWF adc_h
    BANKSEL ADRESL          ; ADRESL is in Bank 1
    MOVF ADRESL,W           ; ADC bits 7:0
    BANKSEL adc_l           ; back to Bank 0
    MOVWF adc_l

    PAGESEL MapAdcToCcp
    CALL    MapAdcToCcp     ; adc_h:adc_l -> ccp_next_h:ccp_next_l
    PAGESEL $

    MOVF ccp_next_l,W
    MOVWF ccp_save_l
    MOVF ccp_next_h,W
    MOVWF ccp_save_h
    MOVLW 1
    MOVWF adc_done
    RETURN
End
 