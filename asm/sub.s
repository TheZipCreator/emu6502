  .org $8000
main:
  lda #$30
  sta $E000
  jsr sub
  lda #$32
  sta $E000
  brk
sub:
  lda #$31
  sta $E000
  rts