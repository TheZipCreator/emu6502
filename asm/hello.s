  .org $8000
main:
  ldx #0
loop:
  lda data,x
  sta $E000
  cmp #0
  inx
  bne loop
  brk
data: 
  .byte 'Hello, World!', $0A, $00