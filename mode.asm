.model tiny
.code
locals
org 100h
Start:
	mov al, cs:[82h]
	mov mess, al
	sub al, '0'
;
	cmp al, 7
	je t
	cmp al, 3
	jg em
t:	
	mov dl, al
	mov bh, cs:[84h]
	mov mess+2, bh
	sub bh, '0'
;	
	mov dh, 0
	mov bp, dx
	cmp byte ptr pages[bp], 0
	je ep
	cmp byte ptr pages[bp], bh
	jle ep
;
	mov ah, 0h
	int 10h
;
	mov ah, 05h
	mov al, bh
	int 10h
	mov dh, 25d-1
	cmp dl, 2
	jge c1
	mov dl, 40d-len
	jmp c2
c1:	mov dl, 80d-len
c2:	int 10h
	mov ah, 02h
	int 10h
	mov al, [mess]
	mov cx, 1
	mov ah, 0ah
	int 10h
;
	inc dl
	mov ah, 02h
	int 10h
	mov al, [mess+1]
	mov cx, 1
	mov ah, 0ah
	int 10h
;
	inc dl
	mov ah, 02h
	int 10h
	mov al, [mess+2]
	mov cx, 1
	mov ah, 0ah
	int 10h
;
	mov ah, 02h
	xor dx, dx
	int 10h
	ret
;
em:
	mov ah, 9h
    mov dx, offset errmode
    int 21h
    ret
ep:
	mov ah, 9h
    mov dx, offset errpage
    int 21h
    ret
mess db 0h, ':', 0h
len = 3
pages db 8h, 8h, 4h, 4h, 0h, 0h, 0h, 8h
errmode db 'Wrong mode number$'
errpage db 'Wrong page number$'
;
end Start