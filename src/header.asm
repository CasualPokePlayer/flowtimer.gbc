INCLUDE "defines.asm"

SECTION "Rst $00", ROM0[$00]
NULL::
	; This traps jumps to $0000, which is a common "default" pointer
	; $FFFF is another one, but reads rIE as the instruction byte
	; Thus, we put two `nop`s that may serve as operands, before soft-crashing
	; The operand will always be 0, so even jumps will work fine. Nice!
	nop
	nop
	rst Crash
	
SECTION "Rst $18", ROM0[$18]
MemcpySmall::
	ld a, [de]
	ld [hli], a
	inc de
	dec c
	jr nz, MemcpySmall
	ret

SECTION "Rst $20", ROM0[$20]
MemsetSmall::
	ld [hli], a
	dec c
	jr nz, MemsetSmall
	ret

SECTION "Rst $38", ROM0[$38]
; Perform a soft-crash. Prints debug info on-screen
Crash::
	di ; Doing this as soon as possible to avoid interrupts messing up
	jp HandleCrash
	
SECTION "VBlank Interrupt", ROM0[$40]
	jp VBlank
	
SECTION "Timer Interrupt", ROM0[$50]
	jp Timer

SECTION "Header", ROM0[$100]
	; This is your ROM's entry point
	; You have 4 bytes of code to do... something
	sub $11
	jr EntryPoint

	; Make sure to allocate some space for the header, so no important
	; code gets put there and later overwritten by RGBFIX.
	; RGBFIX is designed to operate over a zero-filled header, so make
	; sure to put zeros regardless of the padding value. (This feature
	; was introduced in RGBDS 0.4.0, but the -MG etc flags were also
	; introduced in that version.)
	ds $150 - @, 0

SECTION "Entry point", ROM0[$150]
EntryPoint:
	ld sp,wStackBottom
	error nz ; no DMGs allowed
	di
	ldh [rLCDC],a
	ldh [rSCY],a
	ldh [rSCX],a
	ldh [hBeeps],a
	ldh [hButtonPress],a
	ldh [hTime],a
	ldh [hTime+1],a
	ldh [hTime+2],a
	inc a
	ld [rROMB0],a
	ldh [rSPD],a
	; setup timer
	ld a,(256-53)
	ldh [rTMA],a
	ld a,TACF_START|TACF_262KHZ
	ldh [rTAC],a
	ld a,IEF_TIMER|IEF_VBLANK
	ldh [rIE],a
	ld a,P1F_GET_NONE
	ld hl,rP1
	ld [hl],a ; prevent stop bug
	ldh a,[rSPD]
	bit 7,a
	jr nz,Joypad
	stop $69 ; nice speed switch
	; fallthrough
Joypad:
.poll
	res 4,[hl] ; dpad
	xor a
	bit 3,[hl]
	jr z,.pressDetected ; down
	inc a
	bit 2,[hl]
	jr z,.pressDetected ; up
	inc a
	bit 1,[hl]
	jr z,.pressDetected ; left
	inc a
	bit 0,[hl]
	jr z,.pressDetected ; right
	set 4,[hl] ; unset dpad
	res 5,[hl] ; buttons
	inc a
	bit 3,[hl]
	jr z,.pressDetected ; start
	inc a
	bit 2,[hl]
	jr z,.pressDetected ; select
	inc a
	bit 1,[hl]
	jr z,.pressDetected ; b
	inc a
	bit 0,[hl]
	jr z,.pressDetected ; a
	set 5,[hl] ; unset buttons
	jr .poll
.pressDetected
	ldh [hButtonPress],a ; remember the button press, 0-1-2-3-4-5-6-7 -> Down-Up-Left-Right-Start-Select-B-A
	; everything should mostly be set up, we just need to get the timer and vblank interrupt going
	ld a,LCDCF_ON
	ldh [rLCDC],a ; enable LCD
	ld a,(256-53-4)
	ldh [rDIV],a ; reset DIV
	ldh [rTIMA],a ; set TIMA to 200
	ld a,~(IEF_TIMER|IEF_VBLANK)
	ldh [rIF],a
.wait
	ei
	halt ; interrupts will handle it from here
	di
	ldh a,[hBeeps]
	sub 5
	jr nz,.wait
	jp EntryPoint

VBlank:
	reti ; handle this later
Timer:
; we only got 212 cycles to do stuff, so make it count
	lb bc,1,LOW(hTime+2)
	ldh a,[c]
	add b
	daa
	ldh [c],a
	dec c
	dec b
	ldh a,[c]
	adc b
	daa
	ldh [c],a
	dec c
	ldh a,[c]
	adc b
	daa
	ldh [c],a
	; +24 cycles (188 cycles left)
	ld h,HIGH(BeepIntervalsTable)
	ldh a,[hButtonPress]
	add a
	ld l,a
	ld a,[hli]
	ld h,[hl]
	ld l,a
	; +12 cycles (176 cycles left)
	ldh a,[hBeeps]
	ld b,a
	add a
	add b
	add l
	ld l,a
	; +8 cycles (168 cycles left)
	ldh a,[c]
	cp [hl]
	jr nz,.noBeep
	inc c
	inc l
	ldh a,[c]
	cp [hl]
	jr nz,.noBeep
	inc c
	inc l
	ldh a,[c]
	cp [hl]
	jr nz,.noBeep
	; +22 cycles (146 cycles left)
	ld c,LOW(hBeeps)
	ldh a,[c]
	inc a
	ldh [c],a
	ld a,$F1
	ldh [rNR12],a
	ld a,$BF
	ldh [rNR14],a
	; +17 cycles (129 cycles left)
.noBeep
	reti


SECTION "Beep Intervals Table", ROM0[$300]
BeepIntervalsTable:
	dw BeepIntervalsDown
	dw BeepIntervalsUp
	dw BeepIntervalsLeft
	dw BeepIntervalsRight
	dw BeepIntervalsStart
	dw BeepIntervalsSelect
	dw BeepIntervalsB
	dw BeepIntervalsA
	
SECTION "Beep Intervals", ROM0[$310]
BeepIntervals:
BeepIntervalsDown:
	db $11,$50,$00, $11,$85,$00, $12,$20,$00, $12,$55,$00, $12,$90,$00 ; down
BeepIntervalsUp:
	db $11,$50,$00, $11,$85,$00, $12,$20,$00, $12,$55,$00, $12,$90,$00 ; up
BeepIntervalsLeft:
	db $11,$50,$00, $11,$85,$00, $12,$20,$00, $12,$55,$00, $12,$90,$00 ; left
BeepIntervalsRight:
	db $11,$50,$00, $11,$85,$00, $12,$20,$00, $12,$55,$00, $12,$90,$00 ; right
BeepIntervalsStart:
	db $11,$50,$00, $11,$85,$00, $12,$20,$00, $12,$55,$00, $12,$90,$00 ; start
BeepIntervalsSelect:
	db $11,$50,$00, $11,$85,$00, $12,$20,$00, $12,$55,$00, $12,$90,$00 ; select
BeepIntervalsB:
	db $11,$50,$00, $11,$85,$00, $12,$20,$00, $12,$55,$00, $12,$90,$00 ; b
BeepIntervalsA:
	db $11,$50,$00, $11,$85,$00, $12,$20,$00, $12,$55,$00, $12,$90,$00 ; a
	





; This ensures that the stack is at the very end of WRAM
SECTION "Stack", WRAM0[$D000 - STACK_SIZE]
	ds STACK_SIZE
wStackBottom::


SECTION "Vars", HRAM
hBeeps:
	ds 1
hButtonPress:
	ds 1
hTime:
	ds 3
