.model tiny
.386
.code
locals
org 100h
start: jmp main

int8h:
	push ax
	pushf
	call dword ptr cs:[old_int8h]
	mov al, counter
	cmp al, delay
	jge bell ; больше или равно, т.к. delay может меняться.
	inc al
	jmp b
bell:
	mov al, 1
	mov beep, 1
b:	mov counter, al
	pop ax
	iret
counter db 0
delay db 10
beep db 0 ; сигнал. Если 1, Таймер сработал. Обнуляется программой-польователем.
old_int8h dd ?

int9h:
	push ax
	push di
	pushf
	in al, 60h
; Проверим полон ли буфер, т.е. хвост находится в ячейке перед головой.
	mov di, buf_head
	sub di, buf_tail
	cmp di, 1
	je @@full
	cmp di, -buf_len ; хвост в конце буфера, а голова в начале.
	je @@full
; Запишем сканкод в буфер.
	mov di, buf_tail
	mov byte ptr cs:[di], al
; Передвинем хвост вперед.
	cmp buf_tail, offset buf + buf_len - 1
	jne @@not_end
	mov buf_tail, offset buf - 1
@@not_end:
	inc buf_tail
; Отбиваем клавиатуру.
	in al, 61h
	mov ah, al
	or al, 80h
	out 61h, al
	xchg ah, al
	out 61h, al
@@full:
; Отбиваем контроллер.
	mov al, 20h
	out 20h, al
;
	popf
	pop di
	pop ax
	iret
buf_head dw offset buf
buf_tail dw offset buf
buf_len = 5
buf db buf_len dup (?)
old_int9h dd ?

main:
; Определяем видеорежим.
	mov ah, 0fh
	int 10h
	mov mode, al
	mov gpage, bh
	mov cols, ah
	dec ah
	mov deccols, ah
; Очищаем экран. Свдигаем вверх.
	mov ch, 0
	mov cl, 0
	mov dh, 24d
	mov dl, cols
	mov al, 24d
	mov bh, 0
	mov ah, 6h
	int 10h
; Сдвигаем вниз.
	mov ch, 0
	mov cl, 0
	mov dh, 24d
	mov dl, cols
	mov al, 24d
	mov bh, 7h
	mov ah, 6h
	int 10h
; Определяем место в памяти куда писать для заданного режима - левый верхний угол экрана.
	mov cx, 0B800h
	cmp mode, 7h
	jne not7
	mov cx, 0B000h
not7:
	mov bx, 80h
	cmp cols, 80d
	jne small_screen
	mov bx, 100h
small_screen:
	mov al, gpage
	mul bx
	add cx, ax
	push cx
	pop es
; Рисуем стены.
	mov al, 2
	mul cols
	mov span, ax
; Стена № 3.
	mov bh, 0
	mov bl, 24 ; номер последней строки.
	call getshift
	mov ax, wall_color
; Цикл рисования 3-ей стены.
	mov ah, 0
	mov al, cols
	mov ch, 2
	div ch
	mov cx, ax ; число строк в стене
	mov ax, wall_color
wall3:
	mov word ptr es:[di], ax
	add di, 2
	loop wall3
; Стена № 7.
	mov di, 0
	; Сдвигаемся до правго края.
	add di, span
	sub di, 2
	mov cx, 13 ; число строк в стене.
; Цикл рисования 7-oй стены.
	mov ax, wall_color
wall7:
	mov word ptr es:[di], ax
	add di, span
	loop wall7
; Инициализация нулями карты.
	mov cx, 2000
map_init:
	mov bp, cx
	dec bp
	mov map[bp], 0
	loop map_init
; Инициализация змеи.
	mov ah, 0
	mov al, cols
	mov ch, 2
	div ch
	mov bh, al
	mov bl, 12d
	mov ax, snake_color
	call getshift
	mov word ptr es:[di], ax
	mov snake_x[0], bh ; В буфере голова змеи изначально смотрит в сторону увеличения индекса.
	mov snake_y[0], bl
	call incmap
	dec bh
	mov ax, snake_color
	call getshift
	mov word ptr es:[di], ax
	mov snake_x[1], bh
	mov snake_y[1], bl
	call incmap
	dec bh
	mov ax, snake_color
	call getshift
	mov word ptr es:[di], ax
	mov snake_x[2], bh
	mov snake_y[2], bl
	call incmap
	dec bh
	mov ax, snake_color
	call getshift
	mov word ptr es:[di], ax
	mov snake_x[3], bh
	mov snake_y[3], bl
	call incmap
	dec bh
	mov ax, snake_color
	call getshift
	mov word ptr es:[di], ax
	mov snake_x[4], bh
	mov snake_y[4], bl
	call incmap
	mov snake_len, 5
	mov snake_ind_head, 4
	mov snake_ind_tail, 0
	mov inverse_flag, 0
	mov direction, 1
	mov stop_flag, 1
	mov delay, 1d
;-----------------------------------------------------------------------------------------------------
	push es
; Получаем старый вектор в old_int8h.
    mov ax, 3508h ; 35 - код команды получания вектора прерывания. 8 - номер вектора.
    int 21h
    mov word ptr old_int8h, bx
    mov word ptr old_int8h+2, es
; Устанавливаем новый обработчик int8h.
    mov ax, 2508h
    mov dx, offset int8h
    int 21h
; Получаем старый вектор в old_int9h.
    mov ax, 3509h ; 35 - код команды получания вектора прерывания. 9 - номер вектора.
    int 21h
    mov word ptr old_int9h, bx
    mov word ptr old_int9h+2, es
; Устанавливаем новый обработчик int9h.
    mov ax, 2509h
    mov dx, offset int9h
    int 21h
	pop es
;-----------------------------------------------------------------------------------------------------
; Главный цикл. Во время тика таймера выполняет команды. В промежутках проверяет буфер клавиатуры.
i:
	hlt
	cmp beep, 1
	je signal ; Выполнить команду.
	mov bx, buf_head
	cmp bx, buf_tail; проверяем пуст ли буфер клавиатуры.
	je empty
	mov al, cs:[bx]
; Сдвигаем голову.
	cmp bx, offset buf + buf_len - 1
	jne not_end
	mov buf_head, offset buf - 1
not_end:
	inc buf_head
; Если esc, выходим.
	cmp al, 81h
	je key_esc
; Управление stop-флагом.
	cmp al, 39h ; пробел.
	jne not_key_stop
	cmp stop_flag, 0
	je key_stop
	mov stop_flag, 0
	jmp empty
key_stop:
	mov stop_flag, 1
	jmp empty
not_key_stop:
; Увеличение скорости.
	cmp al, 1Eh ; a.
	jne not_key_acceleration
	cmp delay, 1d ; некуда ускоряться
	je max_speed
	dec delay
max_speed:
	jmp empty
not_key_acceleration:
; Уменьшение скорости.
	cmp al, 20h ; d.
	jne not_key_deceleration
	cmp delay, 20d ; некуда замедляться
	je min_speed
	inc delay
min_speed:
	jmp empty
not_key_deceleration:
; Влево
	cmp al, 04bh ; стрелка влево.
	jne not_key_left
	mov direction, 1h
	mov stop_flag, 0
not_key_left:
; Вправо
	cmp al, 04dh ; стрелка вправо.
	jne not_key_right
	mov direction, 2h
	mov stop_flag, 0
not_key_right:
; Вверх
	cmp al, 48h ; стрелка вверх.
	jne not_key_up
	mov direction, 3h
	mov stop_flag, 0
not_key_up:
; Вниз
	cmp al, 50h ; стрелка вниз.
	jne not_key_down
	mov direction, 4h
	mov stop_flag, 0
not_key_down:
; Удлинить
	cmp al, 11h ; w.
	jne not_key_long
	call prolong_if_possible
not_key_long:
; Укоротить
	cmp al, 1Fh ; s.
	jne not_key_short
	call truncate_if_possible
not_key_short:
empty: ; Когда не считан символ и если символ обработан. Выполнение действий не по таймеру.
	jmp i
;-----------------------------------------------------------------------------------------------------
signal:
	mov beep, 0
	cmp stop_flag, 1 ; Идем или стоим.
	je stop
	mov wasnt_prolong, 0
	call prolong
	cmp wasnt_prolong, 1
	je stop
	call truncate
stop:
	jmp i
;-----------------------------------------------------------------------------------------------------
key_esc:
; Возвращаем старые обработчики прерывания.
	mov dx, word ptr cs:[old_int8h]
    mov ds, word ptr cs:[old_int8h+2]
    mov ax, 2508h
    int 21h
	mov dx, word ptr cs:[old_int9h]
    mov ds, word ptr cs:[old_int9h+2]
    mov ax, 2509h
    int 21h
	; Возвращаемся в обычный режим.
	mov ax, 0003h
	int 10h
	ret

prolong_if_possible proc near
	cmp snake_len, snake_max_len
	jge @@do_not_prolong
	mov wasnt_prolong, 0
	call prolong
	cmp wasnt_prolong, 1
	je @@do_not_prolong
	inc snake_len
@@do_not_prolong:
	ret
prolong_if_possible endp

prolong proc near
	cmp direction, 1
	jne @@not_left
	call direction_left
	ret
@@not_left:
	cmp direction, 2
	jne @@not_right
	call direction_right
	ret
@@not_right:
	cmp direction, 3
	jne @@not_up
	call direction_up
	ret
@@not_up:
	cmp direction, 4
	jne @@not_down
	call direction_down
	ret
@@not_down:
	ret
prolong endp

direction_left proc near
	cmp inverse_flag, 0
	jne @@inverse
	mov bp, snake_ind_head
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	; Проверим не надо ли менять голову и хвост местами.
	; Для этого проверим ячейку из которой мы приползли.
	; В буфере голова змеи изначально смотрит в сторону увеличения индекса.
	; Вычтем 1 по модулю буфера.
	mov si, snake_max_size - 1
	call ringdecword
	; Если мы ползем в нее же, то меняем местами голову и хвост.
	mov cl, deccols
	mov ch, bh
	call ringdecbyte
	mov bh, ch
	cmp snake_x[bp], bh
	jne @@not_same_not_inverse
	cmp snake_y[bp], bl
	jne @@not_same_not_inverse
	mov inverse_flag, 1
	; Определим направление противоположной части тела.
	call getopposite
	call prolong
	ret
@@not_same_not_inverse:
	call leftstraight
	ret
@@inverse:
	mov bp, snake_ind_tail
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	; Проверим не надо ли менять голову и хвост местами.
	; Для этого проверим ячейку из которой мы приползли.
	; В буфере голова змеи изначально смотрит в сторону увеличения индекса.
	; Прибавим 1 по модулю буфера.
	mov si, snake_max_size - 1
	call ringincword
	; Если мы ползем в нее же, то меняем местами голову и хвост.
	mov cl, deccols
	mov ch, bh
	call ringdecbyte
	mov bh, ch
	cmp snake_x[bp], bh
	jne @@not_same_inverse
	cmp snake_y[bp], bl
	jne @@not_same_inverse
	mov inverse_flag, 0
	; Определим направление противоположной части тела.
	call getopposite
	call prolong
	ret
@@not_same_inverse:
	call leftbackwards
	ret
direction_left endp

direction_right proc near
	cmp inverse_flag, 0
	jne @@inverse
	mov bp, snake_ind_head
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	; Проверим не надо ли менять голову и хвост местами.
	; Для этого проверим ячейку из которой мы приползли.
	; В буфере голова змеи изначально смотрит в сторону увеличения индекса.
	; Вычтем 1 по модулю буфера.
	mov si, snake_max_size - 1
	call ringdecword
	; Если мы ползем в нее же, то меняем местами голову и хвост.
	mov cl, deccols
	mov ch, bh
	call ringincbyte
	mov bh, ch
	cmp snake_x[bp], bh
	jne @@not_same_not_inverse
	cmp snake_y[bp], bl
	jne @@not_same_not_inverse
	mov inverse_flag, 1
	; Определим направление противоположной части тела.
	call getopposite
	call prolong
	ret
@@not_same_not_inverse:
	call rightstraight
	ret
@@inverse:
	mov bp, snake_ind_tail
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	; Проверим не надо ли менять голову и хвост местами.
	; Для этого проверим ячейку из которой мы приползли.
	; В буфере голова змеи изначально смотрит в сторону увеличения индекса.
	; Прибавим 1 по модулю буфера.
	mov si, snake_max_size - 1
	call ringincword
	; Если мы ползем в нее же, то меняем местами голову и хвост.
	mov cl, deccols
	mov ch, bh
	call ringincbyte
	mov bh, ch
	cmp snake_x[bp], bh
	jne @@not_same_inverse
	cmp snake_y[bp], bl
	jne @@not_same_inverse
	mov inverse_flag, 0
	; Определим направление противоположной части тела.
	call getopposite
	call prolong
	ret
@@not_same_inverse:
	call rightbackwards
	ret
direction_right endp

direction_up proc near
	cmp inverse_flag, 0
	jne @@inverse
	mov bp, snake_ind_head
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	; Проверим не надо ли менять голову и хвост местами.
	; Для этого проверим ячейку из которой мы приползли.
	; В буфере голова змеи изначально смотрит в сторону увеличения индекса.
	; Вычтем 1 по модулю буфера.
	mov si, snake_max_size - 1
	call ringdecword
	; Если мы ползем в нее же, то меняем местами голову и хвост.
	mov cl, 24d ; число строк
	mov ch, bl
	call ringdecbyte
	mov bl, ch
	cmp snake_x[bp], bh
	jne @@not_same_not_inverse
	cmp snake_y[bp], bl
	jne @@not_same_not_inverse
	mov inverse_flag, 1
	; Определим направление противоположной части тела.
	call getopposite
	call prolong
	ret
@@not_same_not_inverse:
	call upstraight
	ret
@@inverse:
	mov bp, snake_ind_tail
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	; Проверим не надо ли менять голову и хвост местами.
	; Для этого проверим ячейку из которой мы приползли.
	; В буфере голова змеи изначально смотрит в сторону увеличения индекса.
	; Прибавим 1 по модулю буфера.
	mov si, snake_max_size - 1
	call ringincword
	; Если мы ползем в нее же, то меняем местами голову и хвост.
	mov cl, 24d ; число строк
	mov ch, bl
	call ringdecbyte
	mov bl, ch
	cmp snake_x[bp], bh
	jne @@not_same_inverse
	cmp snake_y[bp], bl
	jne @@not_same_inverse
	mov inverse_flag, 0
	; Определим направление противоположной части тела.
	call getopposite
	call prolong
	ret
@@not_same_inverse:
	call upbackwards
	ret
direction_up endp

direction_down proc near
	cmp inverse_flag, 0
	jne @@inverse
	mov bp, snake_ind_head
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	; Проверим не надо ли менять голову и хвост местами.
	; Для этого проверим ячейку из которой мы приползли.
	; В буфере голова змеи изначально смотрит в сторону увеличения индекса.
	; Вычтем 1 по модулю буфера.
	mov si, snake_max_size - 1
	call ringdecword
	; Если мы ползем в нее же, то меняем местами голову и хвост.
	mov cl, 24d ; число строк
	mov ch, bl
	call ringincbyte
	mov bl, ch
	cmp snake_x[bp], bh
	jne @@not_same_not_inverse
	cmp snake_y[bp], bl
	jne @@not_same_not_inverse
	mov inverse_flag, 1
	; Определим направление противоположной части тела.
	call getopposite
	call prolong
	ret
@@not_same_not_inverse:
	call downstraight
	ret
@@inverse:
	mov bp, snake_ind_tail
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	; Проверим не надо ли менять голову и хвост местами.
	; Для этого проверим ячейку из которой мы приползли.
	; В буфере голова змеи изначально смотрит в сторону увеличения индекса.
	; Прибавим 1 по модулю буфера.
	mov si, snake_max_size - 1
	call ringincword
	; Если мы ползем в нее же, то меняем местами голову и хвост.
	mov cl, 24d ; число строк
	mov ch, bl
	call ringincbyte
	mov bl, ch
	cmp snake_x[bp], bh
	jne @@not_same_inverse
	cmp snake_y[bp], bl
	jne @@not_same_inverse
	mov inverse_flag, 0
	; Определим направление противоположной части тела.
	call getopposite
	call prolong
	ret
@@not_same_inverse:
	call downbackwards
	ret
direction_down endp

; Укоротить, если есть куда, т.е. змея длиннее 2-x.
truncate_if_possible proc near
	cmp snake_len, 2
	jle @@do_not_truncate
	mov wasnt_prolong, 0
	call truncate
	cmp wasnt_prolong, 1
	je @@do_not_truncate
	dec snake_len
@@do_not_truncate:
	ret
truncate_if_possible endp
	
; Укоротить змею с хвоста.
truncate proc near
	cmp inverse_flag, 1 ; Что удаляем?
	je @@head
@@tail:
	call deletetail
	ret
@@head:
	call deletehead
	ret
truncate endp

; По inverse_flag определяет что есть противоположная часть тела. Если 0, то хвост, иначе голова.
; Устанавливает в direction направление движения задом наперед. Змея не короче 2-x.
getopposite proc near
	cmp inverse_flag, 1
	jne @@head
@@tail:
	mov bp, snake_ind_tail
	; Координаты последней клетки.
	mov dh, snake_x[bp]
	mov dl, snake_y[bp]
	mov si, snake_max_size - 1
	call ringincword
	jmp @@forall
@@head:
	mov bp, snake_ind_head
	; Координаты последней клетки.
	mov dh, snake_x[bp]
	mov dl, snake_y[bp]
	mov si, snake_max_size - 1
	call ringdecword
	jmp @@forall
@@forall:
	; Координаты предпоследней клетки.
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	; Змея не движется по диагонали, поэтому одновременно меняется только одна координата.
	cmp dh, bh
	je @@vertical
@@horizontal:
	mov cl, deccols
	mov ch, bh
	call ringdecbyte
	; Получили ch - координату левее предпоследней клетки тела.
	cmp ch, dh
	je @@left
@@right:
	mov direction, 2
	ret
@@left:
	mov direction, 1
	ret
@@vertical:
	mov cl, deccols
	mov ch, bl
	call ringdecbyte
	; Получили ch - координату выше предпоследней клетки тела.
	cmp ch, dl
	je @@up
@@down:
	mov direction, 4
	ret
@@up:
	mov direction, 3
	ret
getopposite endp

deletehead proc near
	mov bp, snake_ind_head
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	call getshift
	call getmapvalue
	cmp al, 1
	jne @@after_change_color
	mov ax, background_color
	mov word ptr es:[di], ax
@@after_change_color:
	call decmap
	mov snake_x[bp], 0
	mov snake_y[bp], 0
	mov bp, snake_ind_head
	call ringdecword
	mov snake_ind_head, bp
	ret
deletehead endp

deletetail proc near
	mov bp, snake_ind_tail
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	call getshift
	call getmapvalue
	cmp al, 1
	jne @@after_change_color
	mov ax, background_color
	mov word ptr es:[di], ax
@@after_change_color:
	call decmap
	mov snake_x[bp], 0
	mov snake_y[bp], 0
	mov bp, snake_ind_tail
	call ringincword
	mov snake_ind_tail, bp
	ret
deletetail endp

leftbackwards proc near
	; Ползем налево хвостом вперед.
	; Проверим, что нет препятствия.
	mov bp, snake_ind_tail
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	; Вычтем единицу из иксовой координаты хвоста по модулю ширины экрана.
	mov cl, deccols
	mov ch, bh
	call ringdecbyte
	mov bh, ch
	; Получим смещение и посмотрим на его цвет.
	call getshift
	cmp word ptr es:[di], wall_color
	jne @@not_wall
	cmp bl, 24d ; последняя строка.
	jne @@not_wall
	mov stop_flag, 1
	mov wasnt_prolong, 1
	ret
@@not_wall:
	; Сейчас tail голова.
	mov bp, snake_ind_tail
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	mov cl, deccols
	mov ch, bh
	call ringdecbyte
	mov bh, ch
	call getshift
	mov ax, snake_color
	mov word ptr es:[di], ax
	call incmap
	mov bp, snake_ind_tail
	mov si, snake_max_size - 1
	call ringdecword
	mov snake_ind_tail, bp
	mov snake_x[bp], bh
	mov snake_y[bp], bl
	ret
leftbackwards endp

leftstraight proc near
	; Ползем налево головой вперед.
	; Проверим, что нет препятствия.
	mov bp, snake_ind_head
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	; Вычтем единицу из иксовой координаты головы по модулю ширины экрана.
	mov cl, deccols
	mov ch, bh
	call ringdecbyte
	mov bh, ch
	; Получим смещение и посмотрим на его цвет.
	call getshift
	cmp word ptr es:[di], wall_color
	jne @@not_wall
	cmp bl, 24d ; последняя строка.
	jne @@not_wall
	mov stop_flag, 1
	mov wasnt_prolong, 1
	ret
@@not_wall:
	; Сейчас head голова.
	mov bp, snake_ind_head
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	mov cl, deccols
	mov ch, bh
	call ringdecbyte
	mov bh, ch
	call getshift
	mov ax, snake_color
	mov word ptr es:[di], ax
	call incmap
	mov bp, snake_ind_head
	mov si, snake_max_size - 1
	call ringincword
	mov snake_ind_head, bp
	mov snake_x[bp], bh
	mov snake_y[bp], bl
	ret
leftstraight endp

rightbackwards proc near
	; Ползем направо хвостом вперед.
	; Проверим, что нет препятствия.
	mov bp, snake_ind_tail
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	; Прибавим единицу к иксовой координате хвоста по модулю ширины экрана.
	mov cl, deccols
	mov ch, bh
	call ringincbyte
	mov bh, ch
	; Получим смещение и посмотрим на его цвет.
	call getshift
	cmp word ptr es:[di], wall_color
	jne @@not_wall
	mov stop_flag, 1
	mov wasnt_prolong, 1
	ret
@@not_wall:
	; Сейчас tail голова.
	mov bp, snake_ind_tail
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	mov cl, deccols
	mov ch, bh
	call ringincbyte
	mov bh, ch
	call getshift
	mov ax, snake_color
	mov word ptr es:[di], ax
	call incmap
	mov bp, snake_ind_tail
	mov si, snake_max_size - 1
	call ringdecword
	mov snake_ind_tail, bp
	mov snake_x[bp], bh
	mov snake_y[bp], bl
	ret
rightbackwards endp

rightstraight proc near
	; Ползем направо головой вперед.
	; Проверим, что нет препятствия.
	mov bp, snake_ind_head
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	; Прибавим единицу к иксовой координате головы по модулю ширины экрана.
	mov cl, deccols
	mov ch, bh
	call ringincbyte
	mov bh, ch
	; Получим смещение и посмотрим на его цвет.
	call getshift
	cmp word ptr es:[di], wall_color
	jne @@not_wall
	mov stop_flag, 1
	mov wasnt_prolong, 1
	ret
@@not_wall:
	; Сейчас head голова.
	mov bp, snake_ind_head
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	mov cl, deccols
	mov ch, bh
	call ringincbyte
	mov bh, ch
	call getshift
	mov ax, snake_color
	mov word ptr es:[di], ax
	call incmap
	mov bp, snake_ind_head
	mov si, snake_max_size - 1
	call ringincword
	mov snake_ind_head, bp
	mov snake_x[bp], bh
	mov snake_y[bp], bl
	ret
rightstraight endp

upbackwards proc near
	; Ползем вверх хвостом вперед.
	; Проверим, что нет препятствия.
	mov bp, snake_ind_tail
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	; Вычтем единицу из иксовой координаты хвоста по модулю высоты экрана.
	mov cl, 24d
	mov ch, bl
	call ringdecbyte
	mov bl, ch
	; Получим смещение и посмотрим на его цвет.
	call getshift
	cmp word ptr es:[di], wall_color
	jne @@not_wall
	cmp bh, deccols ; последний стролбец.
	jne @@not_wall
	mov stop_flag, 1
	mov wasnt_prolong, 1
	ret
@@not_wall:
	; Сейчас tail голова.
	mov bp, snake_ind_tail
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	mov cl, 24d
	mov ch, bl
	call ringdecbyte
	mov bl, ch
	call getshift
	mov ax, snake_color
	mov word ptr es:[di], ax
	call incmap
	mov bp, snake_ind_tail
	mov si, snake_max_size - 1
	call ringdecword
	mov snake_ind_tail, bp
	mov snake_x[bp], bh
	mov snake_y[bp], bl
	ret
upbackwards endp

upstraight proc near
	; Ползем вверх головой вперед.
	; Проверим, что нет препятствия.
	mov bp, snake_ind_head
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	; Вычтем единицу из игриковой координаты головы по модулю выстоты экрана.
	mov cl, 24d
	mov ch, bl
	call ringdecbyte
	mov bl, ch
	; Получим смещение и посмотрим на его цвет.
	call getshift
	cmp word ptr es:[di], wall_color
	jne @@not_wall
	cmp bh, deccols ; последний стролбец.
	jne @@not_wall
	mov stop_flag, 1
	mov wasnt_prolong, 1
	ret
@@not_wall:
	; Сейчас head голова.
	mov bp, snake_ind_head
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	mov cl, 24d
	mov ch, bl
	call ringdecbyte
	mov bl, ch
	call getshift
	mov ax, snake_color
	mov word ptr es:[di], ax
	call incmap
	mov bp, snake_ind_head
	mov si, snake_max_size - 1
	call ringincword
	mov snake_ind_head, bp
	mov snake_x[bp], bh
	mov snake_y[bp], bl
	ret
upstraight endp

downbackwards proc near
	; Ползем вниз хвостом вперед.
	; Проверим, что нет препятствия.
	mov bp, snake_ind_tail
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	; Прибавим единицу к иксовой координате хвоста по модулю выстоты экрана.
	mov cl, 24d
	mov ch, bl
	call ringincbyte
	mov bl, ch
	; Получим смещение и посмотрим на его цвет.
	call getshift
	cmp word ptr es:[di], wall_color
	jne @@not_wall
	mov stop_flag, 1
	mov wasnt_prolong, 1
	ret
@@not_wall:
	; Сейчас tail голова.
	mov bp, snake_ind_tail
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	mov cl, 24d
	mov ch, bl
	call ringincbyte
	mov bl, ch
	call getshift
	mov ax, snake_color
	mov word ptr es:[di], ax
	call incmap
	mov bp, snake_ind_tail
	mov si, snake_max_size - 1
	call ringdecword
	mov snake_ind_tail, bp
	mov snake_x[bp], bh
	mov snake_y[bp], bl
	ret
downbackwards endp

downstraight proc near
	; Ползем вниз головой вперед.
	; Проверим, что нет препятствия.
	mov bp, snake_ind_head
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	; Прибавим единицу к иксовой координате головы по модулю выстоты экрана.
	mov cl, 24d
	mov ch, bl
	call ringincbyte
	mov bl, ch
	; Получим смещение и посмотрим на его цвет.
	call getshift
	cmp word ptr es:[di], wall_color
	jne @@not_wall
	mov stop_flag, 1
	mov wasnt_prolong, 1
	ret
@@not_wall:
	; Сейчас head голова.
	mov bp, snake_ind_head
	mov bh, snake_x[bp]
	mov bl, snake_y[bp]
	mov cl, 24d
	mov ch, bl
	call ringincbyte
	mov bl, ch
	call getshift
	mov ax, snake_color
	mov word ptr es:[di], ax
	call incmap
	mov bp, snake_ind_head
	mov si, snake_max_size - 1
	call ringincword
	mov snake_ind_head, bp
	mov snake_x[bp], bh
	mov snake_y[bp], bl
	ret
downstraight endp

; В bh получает координату x, в bl координату y.
; Устанавливает в di сдвиг в памяти к заданной координате.
getshift proc near
	push ax
	mov ax, span ; байт ah нулевой. Выполняется байтовое умножение.
	mov ah, 0
	mul bl
	mov di, ax
	mov al, 2
	mul bh
	add di, ax
	pop ax
	ret
getshift endp

; По адресу di возвращает индекс в map.
getmapindex proc near
	push ax
	push cx
	push dx
	mov dx, 0
	mov ax, di
	mov cx, 2
	div cx
	mov bp, ax
	pop dx
	pop cx
	pop ax
	ret
getmapindex endp

; Возвращает в al значение map для адреса di.
getmapvalue proc near
	push bp
	call getmapindex
	mov al, map[bp]
	pop bp
	ret
getmapvalue endp

; Увеличивает счетчик клетки карты для адреса di.
incmap proc near
	push bp
	call getmapindex
	inc map[bp]
	pop bp
	ret
incmap endp

; Уменьшает счетчик клетки карты для адреса di.
decmap proc near
	push bp
	call getmapindex
	dec map[bp]
	pop bp
	ret
decmap endp

; Вычтем 1 из bp по модулю si.
ringdecword proc near
	cmp bp, 0
	je @@do_ring
	dec bp
	ret
@@do_ring:
	mov bp, si
	ret
ringdecword endp

; Вычтем 1 из ch по модулю cl.
ringdecbyte proc near
	cmp ch, 0
	je @@do_ring
	dec ch
	ret
@@do_ring:
	mov ch, cl
	ret
ringdecbyte endp

; Прибавим 1 из bp по модулю si.
ringincword proc near
	cmp bp, si
	je @@do_ring
	inc bp
	ret
@@do_ring:
	mov bp, 0
	ret
ringincword endp

; Прибавим 1 из ch по модулю cl.
ringincbyte proc near
	cmp ch, cl
	je @@do_ring
	inc ch
	ret
@@do_ring:
	mov ch, 0
	ret
ringincbyte endp

; В al передается символ для вывода в левый верхний угол.
debug proc near
	push ax
	push di
	mov ax, 1E1Eh
	mov di, 0
	mov word ptr es:[di], ax
	pop di
	pop ax
	ret
debug endp

wasnt_prolong db ?; единица предупреждает, что змея не удлинилась из-за стены или других проблем в прошлой попытке.
mode db ?
gpage db ?
cols db ? ; число текстовых колонок в видеорежиме.
deccols db ? ; cols - 1
span dw ? ; сдвиг, чтобы перейти на другую строку.
wall_color = 1EB0h
background_color = 0720h
stop_flag db ? ; 1 означает змея стоит.
direction db ? ; 1 влево, 2 вправо, 3 вверх, 4 вниз.
snake_color = 6E05h
snake_len dw ? ; фактическая длина змеи.
snake_ind_head dw ? ; индекс ячейки с головой змеи в массивах snake
snake_ind_tail dw ? ; индекс ячейки с хвостом змеи в массивах snake
inverse_flag db ? ; 0, если голова и хвост являются самими собой, 1 - поменяли значения наоборот.
snake_max_size = 1000d ; размер буфера под змею.
snake_max_len = snake_max_size - 1 ; максимальная длина змеи.
snake_x db snake_max_size dup (?)
snake_y db snake_max_size dup (?)
map db 2000 dup (?) ; содержит количество слоев змеи в этой клетке. Максимально 200d, т.к. змея не длинее 1000.
end start