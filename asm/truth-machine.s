  .org $8000
main:
  lda $E000
  sta $E000
  cmp #$31
  bne end
loop:
  sta $E000
  jmp loop
end:
  brk