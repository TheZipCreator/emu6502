  .org $8000
main:
  ; get num 1
  lda $E000
  sta $E000
  sta num1
  lda #$0A
  sta $E000
  ; get num 2
  lda $E000
  sta $E000
  sta num2
  lda #$0A
  sta $E000
  ; write num1
  lda num1
  sta $E000
  ; compare
  cmp num2
  bcc lt
  lda #$3E
  sta $E000
  jmp end
lt:
  lda #$3C
  sta $E000
end:
  lda num2
  sta $E000
  brk

num1: .byte $00
num2: .byte $00