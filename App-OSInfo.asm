;@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
;@                                                                            @
;@                           S y m b O S    I n f o                           @
;@                                                                            @
;@             (c) 2004-2021 by Prodatron / SymbiosiS (Jörn Mika)             @
;@                                                                            @
;@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

relocate_start

;==============================================================================
;### CODE AREA ################################################################
;==============================================================================

;### APPLICATION HEADER #######################################################

;header structure
prgdatcod       equ 0           ;Length of the code area (OS will place this area everywhere)
prgdatdat       equ 2           ;Length of the data area (screen manager data; OS will place this area inside a 16k block of one 64K bank)
prgdattra       equ 4           ;Length of the transfer area (stack, message buffer, desktop manager data; placed between #c000 and #ffff of a 64K bank)
prgdatorg       equ 6           ;Original origin of the assembler code
prgdatrel       equ 8           ;Number of entries in the relocator table
prgdatstk       equ 10          ;Length of the stack in bytes
prgdatrsv       equ 12          ;*reserved* (3 bytes)
prgdatnam       equ 15          ;program name (24+1[0] chars)
prgdatflg       equ 40          ;flags (+1=16colour icon available)
prgdat16i       equ 41          ;file offset of 16colour icon
prgdatrs2       equ 43          ;*reserved* (5 bytes)
prgdatidn       equ 48          ;"SymExe10" SymbOS executable file identification
prgdatcex       equ 56          ;additional memory for code area (will be reserved directly behind the loaded code area)
prgdatdex       equ 58          ;additional memory for data area (see above)
prgdattex       equ 60          ;additional memory for transfer area (see above)
prgdatres       equ 62          ;*reserviert* (26 bytes)
prgdatver       equ 88          ;required OS version (minor, major)
prgdatism       equ 90          ;Application icon (small version), 8x8 pixel, SymbOS graphic format
prgdatibg       equ 109         ;Application icon (big version), 24x24 pixel, SymbOS graphic format
prgdatlen       equ 256         ;length of header

prgpstdat       equ 6           ;start address of the data area
prgpsttra       equ 8           ;start address of the transfer area
prgpstspz       equ 10          ;additional sub process or timer IDs (4*1)
prgpstbnk       equ 14          ;64K ram bank (1-8), where the application is located
prgpstmem       equ 48          ;additional memory areas; 8 memory areas can be registered here, each entry consists of 5 bytes
                                ;00  1B  Ram bank number (1-8; if 0, the entry will be ignored)
                                ;01  1W  Address
                                ;03  1W  Length
prgpstnum       equ 88          ;Application ID
prgpstprz       equ 89          ;Main process ID

prgcodbeg   dw prgdatbeg-prgcodbeg  ;length of code area
            dw prgtrnbeg-prgdatbeg  ;length of data area
            dw prgtrnend-prgtrnbeg  ;length of transfer area
prgdatadr   dw #1000                ;original origin                    POST address data area
prgtrnadr   dw relocate_count       ;number of relocator table entries  POST address transfer area
prgprztab   dw prgstk-prgtrnbeg     ;stack length                       POST table processes
            dw 0                    ;*reserved*
prgbnknum   db 0                    ;*reserved*                         POST bank number
            db "SymbOS Information":ds 6:db 0 ;Name
            db 0                    ;flags (+1=16c icon)
            dw 0                    ;16c icon offset
            ds 5                    ;*reserved*
prgmemtab   db "SymExe10"           ;SymbOS-EXE-identifier              POST table reserved memory areas
            dw 0                    ;additional code memory
            dw 0                    ;additional data memory
            dw 0                    ;additional transfer memory
            ds 26                   ;*reserviert*
            db 0,3                  ;required OS version (3.0)

prgicnsml   db 2,8,8,#00,#00,#00,#46,#00,#8C,#00,#46,#23,#8C,#33,#08,#33,#8C,#00,#00
prgicnbig   db 6,24,24
            ds 6*24,#FF


;### PRGPRZ -> Application process
dskprzn     db 2
sysprzn     db 3
windatprz   equ 3   ;Process ID
prgwin      db 0    ;main window ID

prgprz  ld a,(prgprzn)
        ld (syswininf+windatprz),a

        call syschk

        ld c,MSC_DSK_WINOPN
        ld a,(prgbnknum)
        ld b,a
        ld de,syswininf
        call msgsnd             ;open window
prgprz1 call msgdsk             ;get message -> IXL=Status, IXH=sender ID
        cp MSR_DSK_WOPNER
        jp z,prgend             ;memory full -> quit process
        cp MSR_DSK_WOPNOK
        jr nz,prgprz1           ;message is not "window has been opened" -> ignore
        ld a,(prgmsgb+4)
        ld (prgwin),a           ;window has been opened -> store ID

prgprz0 call msgget             ;*** check for messages
        jr nc,prgprz0
        cp MSR_DSK_WCLICK       ;* window has been clicked?
        jr nz,prgprz0
        ld a,(iy+2)             ;* yes, check what exactly
        cp DSK_ACT_CLOSE        ;* close clicked
        jr z,prgend
        cp DSK_ACT_CONTENT      ;* content clicked
        jr nz,prgprz0
        ld l,(iy+8)
        ld h,(iy+9)
        ld a,l
        or h
        jr z,prgprz0

;### PRGEND -> quit application
prgend  ld a,(prgprzn)
        db #dd:ld l,a
        ld a,(sysprzn)
        db #dd:ld h,a
        ld iy,prgmsgb
        ld (iy+0),MSC_SYS_PRGEND    ;send "please kill me" message to system manager
        ld a,(prgcodbeg+prgpstnum)
        ld (iy+1),a
        rst #10
prgend0 rst #30                     ;wait for death
        jr prgend0


;==============================================================================
;### SUB-ROUTINES #############################################################
;==============================================================================

;### MSGGET -> check for message for application
;### Output     CF=0 -> keine Message vorhanden, CF=1 -> IXH=Absender, (recmsgb)=Message, A=(recmsgb+0), IY=recmsgb
msgget  ld a,(prgprzn)
        db #dd:ld l,a           ;IXL=our own process ID
        db #dd:ld h,-1          ;IYL=sender ID (-1 = receive messages from any sender)
        ld iy,prgmsgb           ;IY=Messagebuffer
        rst #08                 ;get Message -> IXL=Status, IXH=sender ID
        or a
        db #dd:dec l
        ret nz
        ld iy,prgmsgb
        ld a,(iy+0)
        or a
        jp z,prgend
        scf
        ret

;### MSGDSK -> wait for a message from the desktop manager
;### Ausgabe    (recmsgb)=Message, A=(recmsgb+0), IY=recmsgb
;### Veraendert 
msgdsk  call msgget
        jr nc,msgdsk            ;no Message
        ld a,(dskprzn)
        db #dd:cp h
        jr nz,msgdsk            ;Message from someone else -> ignore
        ld a,(prgmsgb)
        ret

;### MSGSND -> send message to desktop process
;### Eingabe    C=command, B/E/D/L/H=Parameter1/2/3/4/5
msgsnd  ld a,(dskprzn)
msgsnd1 db #dd:ld h,a
        ld a,(prgprzn)
        db #dd:ld l,a
        ld iy,prgmsgb
        ld (iy+0),c
        ld (iy+1),b
        ld (iy+2),e
        ld (iy+3),d
        ld (iy+4),l
        ld (iy+5),h
        rst #10
        ret

;### SYSCHK -> get version string
syschk  ld e,7
        ld hl,jmp_sysinf
        rst #28             ;DE=System, IX=Data, IYL=Databank
        push iy
        ld e,8
        ld hl,jmp_sysinf
        rst #28                 ;IY=Adr
        push iy:pop hl
        inc hl:inc hl
        ld de,systxtinf3t
        ld a,(prgbnknum)
        add a:add a:add a:add a
        pop bc
        add c
        ld bc,14
        rst #20:dw jmp_bnkcop   ;kopieren
        ret


;==============================================================================
;### DATA AREA ################################################################
;==============================================================================

prgdatbeg

;### SYMBOS INFO ##############################################################

systiticn   db 2,8,8,#00,#00,#00,#46,#00,#8C,#00,#46,#23,#8C,#33,#08,#33,#8C,#00,#00
systitinft  db "About SymbOS",0
systxtinf1t db "Millennium Multitasking Operating System",0
systxtinf2t db "for CPC&MSX&PCW&EP&NC&SVM&NEXT",0

systxtinf3t db "############## (c)SymbiosiS 2000-2024",0

systxtinf4t db "Concept, design and main implementation",0
systxtinf5t db "by Prodatron/SymbiosiS (Joern Mika)",0

systxtinf9t db "Respects to the whole 8bit community!",0

systxtsub00 db "Additional credits...",0
systxtsub10 db "EDOZ",0
systxtsub11 db   "User guide, quality assurance and",0
systxtsub12 db   "general support",0
systxtsubd0 db "TREBMINT",0
systxtsubd1 db   "Quigs IDE, G9K game environment,",0
systxtsubd2 db   "general consulting and support",0
systxtsubc0 db "INSANE/altair^rabenauge^tscc",0
systxtsubc1 db   "SymbOSVM for 32/64bit Win/Mac/",0
systxtsubc2 db   "InsaneOS/Linux/Genode platforms",0
systxtsubb0 db "EINAR SAUKAS & INTROSPEC",0
systxtsubb1 db   "ZX0 [turbo un]compressor",0
systxtsubj0 db "TARGHAN & MAARTEN LOOR",0
systxtsubj1 db   "PSG (AT2) & OPL4 (MOD) routines",0
systxtsub20 db "NYYRIKKI",0
systxtsub21 db   "technical consulting, MSX boot",0
systxtsub22 db   "routines, docs, crazy stuff",0
systxtsubf0 db "ZOZOSOFT & LGB & GFLOREZ",0
systxtsubf1 db   "technical consulting (EP, PCW)",0
systxtsubg0 db "ISTVAN VARGA & GECO",0
systxtsubg1 db   "AY emulation with Dave (EP)",0
systxtsub30 db "CBSFOX",0
systxtsub31 db   "MSX FDC autodetection",0

systxtsub40 db "Many thanx to...",0
systxtsubk0 db "PREVTENET",0
systxtsubk1 db   "for creating awesome apps,",0
systxtsubk2 db   "media files and great ideas",0
systxtsub90 db "TMT LOGIC",0
systxtsub91 db   "for the powerful SYMBiFACE III",0
systxtsubh0 db "GFLOREZ & TMT LOGIC",0
systxtsubh1 db   "for adapters that make even HW",0
systxtsubh2 db   "expansions platform independant",0
systxtsub60 db "RICHARD WILSON",0
systxtsub61 db   "for WinApe, best CPC emulator",0
systxtsub70 db "OPENMSX TEAM",0
systxtsub71 db   "for the great openMSX emulator",0
systxtsub80 db "JOHN ELLIOTT",0
systxtsub81 db   "for the PCW emulator Joyce",0
systxtsube0 db "ISTVANV",0
systxtsube1 db   "for Ep128Emu, my fav EP emulator",0
systxtsubi0 db "RUSSELL MARKS",0
systxtsubi1 db   "for nc100em NC100/200 emulator",0
systxtsuba0 db "CPCWIKI, MRC, ENTERPRISEFOREVER",0
systxtsuba1 db   "for all your fantastic (!) support",0

sysbutok    db "Ok",0

syslogo db 42,168,25
db #F0,#F0,#F0,#FF,#FF,#FF,#FE,#F3,#FF,#F0,#F0,#F0,#FF,#F3,#F8,#F0,#F0,#F0,#F0,#F7,#F1,#FF,#FF,#F0,#F0,#F0,#F0,#F0,#F0,#F0,#F3,#FE,#F0,#F0,#F0,#F0,#F0,#F1,#FF,#FF,#FF,#FC
db #F0,#F0,#8F,#0F,#0F,#0F,#0F,#CF,#0F,#7F,#F0,#C7,#0F,#8F,#3E,#F0,#F0,#F0,#F0,#8F,#4B,#0F,#0F,#3E,#F0,#F0,#F0,#F0,#F0,#F1,#0F,#0F,#3E,#F0,#F0,#F0,#F1,#0F,#0F,#0F,#0F,#3E
db #F0,#E3,#7C,#FF,#FF,#FF,#EF,#DF,#F6,#7F,#F0,#3D,#DF,#BF,#9F,#F0,#F0,#F0,#F1,#7F,#5F,#FF,#FF,#CF,#F0,#F0,#F0,#F0,#F0,#87,#FF,#FF,#CF,#F0,#F0,#F0,#CF,#FF,#FF,#FF,#FF,#D7
db #F0,#96,#F3,#F8,#F0,#F0,#E1,#DB,#F4,#BD,#F1,#7B,#D2,#BD,#DB,#F8,#F0,#F0,#E3,#FC,#5F,#F0,#F0,#F3,#7C,#F0,#F0,#F0,#F1,#7C,#F0,#F0,#FF,#3C,#F0,#F1,#BE,#F0,#F0,#F0,#F1,#D7
db #F0,#3C,#F6,#F0,#F0,#F0,#E1,#EB,#F6,#B5,#E9,#F2,#D6,#BD,#E9,#FC,#F0,#F0,#D3,#F8,#5F,#F0,#F0,#F0,#BC,#F0,#F0,#F0,#E3,#F8,#F0,#FC,#F3,#D6,#F0,#E7,#78,#F0,#F0,#F0,#F1,#D7
db #E1,#78,#FC,#F0,#F0,#F0,#E1,#EB,#F2,#D6,#EB,#0F,#3F,#BD,#F8,#7E,#F0,#F0,#B7,#F0,#5F,#F0,#F0,#F0,#96,#F0,#F0,#F0,#D6,#F0,#E2,#32,#F0,#EB,#F0,#EF,#F0,#F0,#F0,#F0,#F1,#D7
db #E3,#F1,#F8,#F0,#F0,#F0,#E1,#EB,#F2,#D2,#FF,#FF,#FF,#B5,#F8,#B7,#F0,#F0,#7E,#F0,#5F,#F0,#F0,#F0,#D6,#F0,#F0,#F0,#BC,#F0,#00,#11,#F8,#E5,#F8,#DE,#F0,#F0,#F0,#F0,#F3,#B6
db #D2,#F1,#E3,#0F,#0F,#0F,#0F,#FF,#7B,#D3,#C7,#0F,#7F,#B5,#F8,#D3,#F8,#E1,#FC,#F0,#4F,#0F,#0F,#0F,#1E,#F0,#F0,#F0,#7C,#E0,#CC,#FF,#FE,#F6,#79,#BE,#F0,#CF,#0F,#0F,#0F,#3C
db #D6,#F3,#96,#F3,#F8,#F0,#F0,#FE,#79,#E3,#D6,#FC,#7B,#B5,#F8,#E3,#FC,#D3,#F8,#F0,#7C,#F0,#F0,#F0,#F0,#F0,#F0,#F1,#78,#F3,#00,#00,#76,#F3,#7F,#BC,#F3,#3F,#F0,#F0,#F0,#F0
db #B4,#F2,#7C,#F6,#F0,#F0,#F0,#F0,#7D,#E9,#BE,#F8,#7B,#B5,#F8,#F1,#7C,#97,#F8,#F0,#4F,#0F,#0F,#0F,#0F,#0F,#F8,#F1,#78,#91,#00,#22,#10,#F3,#B7,#7C,#E7,#78,#F0,#F0,#F0,#F0
db #BC,#E7,#78,#FC,#F0,#F0,#F0,#F0,#BD,#F9,#3F,#E9,#FA,#B5,#F8,#F0,#BE,#3F,#F0,#F0,#5F,#FF,#FF,#FF,#FF,#FF,#3E,#E3,#F8,#91,#00,#11,#F8,#F1,#B6,#78,#EF,#F0,#F0,#F0,#F0,#F0
db #7C,#E7,#F1,#F8,#F0,#F7,#FF,#F0,#B4,#F8,#F0,#E1,#F6,#B5,#F8,#F0,#B7,#7E,#F0,#F0,#5F,#F0,#F0,#F0,#F0,#F0,#C7,#E3,#F0,#FF,#88,#00,#32,#F1,#B6,#79,#DA,#F0,#F0,#F0,#FF,#FE
db #0F,#0F,#FF,#F0,#F0,#87,#0F,#FF,#B6,#FC,#F0,#E3,#F4,#B5,#F8,#F0,#C7,#FC,#F0,#F0,#5F,#F0,#F0,#F0,#F0,#F0,#E3,#6B,#F0,#F7,#88,#00,#99,#F9,#B7,#0F,#1E,#F0,#F0,#F7,#0F,#1F
db #F0,#FF,#FF,#F0,#F0,#BC,#ED,#F3,#D2,#F4,#F0,#D3,#F4,#B5,#F8,#F0,#C7,#FC,#F0,#F0,#5F,#F0,#F0,#F0,#F0,#F0,#F1,#6F,#F0,#E6,#00,#00,#11,#F1,#B7,#FF,#F8,#F0,#F0,#FC,#7B,#D3
db #F0,#F0,#F0,#F0,#F0,#78,#E9,#F3,#D2,#F4,#F0,#D2,#FC,#B5,#F8,#F0,#C7,#FC,#F0,#F0,#5F,#F0,#F0,#F0,#F0,#F0,#F0,#AF,#F0,#80,#00,#00,#BB,#F1,#B4,#F0,#F0,#F0,#F0,#ED,#FB,#D2
db #F0,#F0,#F0,#F0,#E1,#F9,#DB,#F2,#E3,#F6,#F0,#D6,#F8,#B5,#F9,#0F,#3F,#0F,#1F,#F0,#4F,#0F,#0F,#0F,#0F,#0F,#0F,#2F,#F8,#80,#22,#00,#32,#F1,#B4,#F0,#F0,#F0,#F1,#CB,#F3,#D6
db #F0,#F0,#F0,#F0,#D7,#F7,#D2,#F6,#E1,#F2,#F0,#B5,#F8,#B5,#F9,#7F,#FC,#F3,#9F,#F0,#7D,#FF,#FF,#FF,#FF,#FF,#FF,#FD,#78,#E2,#00,#44,#76,#F3,#BC,#F0,#F0,#F0,#F3,#9E,#F2,#B6
db #0F,#0F,#0F,#0F,#3F,#FC,#96,#F4,#E1,#FB,#F0,#B5,#F8,#B5,#F9,#7E,#F0,#F0,#D7,#F0,#4F,#0F,#0F,#0F,#0F,#0F,#0F,#7D,#7C,#F1,#88,#CC,#B8,#F2,#7F,#0F,#0F,#0F,#0F,#7C,#F6,#BC
db #7F,#FF,#FF,#FF,#F0,#F0,#BC,#FC,#F1,#7B,#F0,#7D,#F0,#B5,#F9,#7E,#F0,#F0,#D7,#F0,#5F,#FF,#FF,#FF,#FF,#FF,#FF,#3C,#BC,#F0,#EE,#00,#F0,#F7,#7F,#7F,#FF,#FF,#FC,#F0,#FC,#78
db #7C,#F8,#F0,#F0,#F0,#F0,#79,#F8,#F1,#7B,#F0,#7D,#F0,#B5,#F9,#7E,#F0,#F0,#D7,#F0,#5F,#F0,#F0,#F0,#F0,#F0,#F0,#3C,#9E,#F0,#F3,#74,#F0,#EF,#F7,#78,#F0,#F0,#F0,#F1,#E9,#F8
db #7C,#F8,#F0,#F0,#F0,#E3,#FB,#F0,#F1,#7B,#F0,#7D,#F0,#B5,#F9,#7E,#F0,#F0,#D7,#F0,#5F,#F0,#F0,#F0,#F0,#F0,#F1,#78,#C7,#F0,#F0,#F0,#F1,#DE,#F7,#78,#F0,#F0,#F0,#F3,#D3,#F0
db #7C,#F8,#F0,#F0,#F0,#D7,#FE,#F0,#F1,#7B,#F0,#7D,#F0,#B5,#F9,#7E,#F0,#F0,#D7,#F0,#5F,#F0,#F0,#F0,#F0,#F0,#E3,#F8,#E3,#78,#F0,#F0,#F3,#3C,#F7,#78,#F0,#F0,#F0,#F6,#BE,#F0
db #7C,#F8,#F0,#F0,#F3,#3F,#F8,#F0,#F1,#7B,#F0,#7D,#F0,#B5,#F9,#7E,#F0,#F0,#D7,#F0,#5F,#F0,#F0,#F0,#F0,#F0,#DF,#F0,#F0,#9F,#F0,#F0,#EF,#F8,#F7,#78,#F0,#F0,#F3,#EF,#78,#F0
db #0F,#0F,#0F,#0F,#0F,#FE,#F0,#F0,#F1,#7F,#FF,#7F,#F0,#87,#0F,#7C,#F0,#F0,#C7,#0F,#5F,#FF,#FF,#FF,#FF,#EF,#3C,#F0,#F0,#E3,#3F,#EF,#1E,#F0,#F3,#0F,#0F,#0F,#0F,#1F,#F0,#F0
db #F7,#FF,#FF,#FF,#FF,#F0,#F0,#F0,#F0,#8F,#0F,#F8,#F0,#F3,#FF,#F0,#F0,#F0,#F3,#FF,#CB,#0F,#0F,#0F,#0F,#1F,#F0,#F0,#F0,#F0,#CF,#1F,#F8,#F0,#F0,#FF,#FF,#FF,#FF,#FC,#F0,#F0


;==============================================================================
;### TRANSFER AREA ############################################################
;==============================================================================

prgtrnbeg
;### PRGPRZS -> Stack for application process
        ds 128
prgstk  ds 6*2
        dw prgprz
prgprzn db 0
prgmsgb ds 14

;### SYMBOS INFO ##############################################################

syswininf   dw #1501,0,75,02,174,171,0,0,174,171,174,171,174,171,systiticn,systitinft,0,0,sysgrpinf,0,0:ds 136+14
sysgrpinf   db 12,0:dw sysdatinf,0,0,12*256+12,0,0,12
sysdatinf
dw 00,255*256+0 ,2,           0, 0,1000,1000,0         ;00 Background
dw 00,255*256+0 ,1,          02, 1,   170,27,0         ;01 Logo-Background
dw 00,255*256+8, syslogo,    03, 2,   168,25,0         ;02 Logo
dw 00,255*256+1 ,systxtinf1, 05,25+ 5,164, 8,0         ;03 Description 1
dw 00,255*256+1 ,systxtinf2, 05,25+13,164, 8,0         ;04 Description 2
dw 00,255*256+1 ,systxtinf3, 02,25+22,170, 8,0         ;05 Description 3
dw 00,255*256+1 ,systxtinf4, 05,25+31,164, 8,0         ;06 Description 4
dw 00,255*256+1 ,systxtinf5, 05,25+39,164, 8,0         ;07 Description 5
dw 00,255*256+2 ,4*1+3     , 04,25+49,166,71,0         ;08 Greetings frame
dw 00,255*256+25,sysobjsup , 05,25+50,164,69,0         ;09 Greetings window
dw 00,255*256+1 ,systxtinf9, 05,65+82,164, 8,0         ;10 Description 9
dw prgend,255*256+16,sysbutok  , 62,65+92,50,12,0      ;11 "Ok"-Button

systxtinf1  dw systxtinf1t,4*3+2+512
systxtinf2  dw systxtinf2t,4*3+2+512
systxtinf3  dw systxtinf3t,4*0+3+512+128
systxtinf4  dw systxtinf4t,4*1+2+512
systxtinf5  dw systxtinf5t,4*1+2+512
systxtinf9  dw systxtinf9t,4*3+2+512

;Greetings-Subfenster
sysobjsup   dw sysgrpwin,152,374,0,0,2
sysgrpwin   db 47,0:dw sysdatwin,0,0,00*256+00,0,0,00

sysdatwin
dw 00,255*256+0 ,0,           0, 0,1000,1000,0         ;?? Background
dw 00,255*256+1 ,sysobjsub00,01,8*00+1,158, 8,0        ;?? Title 1
dw 00,255*256+0 ,3,          01,8*00+10,158,1,0        ;?? Line 1
dw 00,255*256+1 ,sysobjsub10,01,8*01+5,158, 8,0        ;?? Description
dw 00,255*256+1 ,sysobjsub11,11,8*02+5,158, 8,0        ;?? Description
dw 00,255*256+1 ,sysobjsub12,11,8*03+5,158, 8,0        ;?? Description
dw 00,255*256+1 ,sysobjsubd0,01,8*04+5,158, 8,0        ;?? Description
dw 00,255*256+1 ,sysobjsubd1,11,8*05+5,158, 8,0        ;?? Description
dw 00,255*256+1 ,sysobjsubd2,11,8*06+5,158, 8,0        ;?? Description
dw 00,255*256+1 ,sysobjsubc0,01,8*07+5,158, 8,0        ;?? Description
dw 00,255*256+1 ,sysobjsubc1,11,8*08+5,158, 8,0        ;?? Description
dw 00,255*256+1 ,sysobjsubc2,11,8*09+5,158, 8,0        ;?? Description
dw 00,255*256+1 ,sysobjsubb0,01,8*10+5,158, 8,0        ;?? Description
dw 00,255*256+1 ,sysobjsubb1,11,8*11+5,158, 8,0        ;?? Description

dw 00,255*256+1 ,sysobjsubj0,01,8*12+5,158, 8,0        ;?? Description
dw 00,255*256+1 ,sysobjsubj1,11,8*13+5,158, 8,0        ;?? Description

dw 00,255*256+1 ,sysobjsub20,01,8*14+5,158, 8,0        ;?? Description
dw 00,255*256+1 ,sysobjsub21,11,8*15+5,158, 8,0        ;?? Description
dw 00,255*256+1 ,sysobjsub22,11,8*16+5,158, 8,0        ;?? Description
dw 00,255*256+1 ,sysobjsubf0,01,8*17+5,158, 8,0        ;?? Description
dw 00,255*256+1 ,sysobjsubf1,11,8*18+5,158, 8,0        ;?? Description
dw 00,255*256+1 ,sysobjsubg0,01,8*19+5,158, 8,0        ;?? Description
dw 00,255*256+1 ,sysobjsubg1,11,8*20+5,158, 8,0        ;?? Description
dw 00,255*256+1 ,sysobjsub30,01,8*21+5,158, 8,0        ;?? Description
dw 00,255*256+1 ,sysobjsub31,11,8*22+5,158, 8,0        ;?? Description
dw 00,255*256+1 ,sysobjsub40,01,8*23+14,158, 8,0       ;?? Title 2
dw 00,255*256+0 ,3,          01,8*23+23,158,1,0        ;?? Line 2
dw 00,255*256+1 ,sysobjsubk0,01,8*24+19,158, 8,0       ;?? Description
dw 00,255*256+1 ,sysobjsubk1,11,8*25+19,158, 8,0       ;?? Description
dw 00,255*256+1 ,sysobjsubk2,11,8*26+19,158, 8,0       ;?? Description
dw 00,255*256+1 ,sysobjsub90,01,8*27+19,158, 8,0       ;?? Description
dw 00,255*256+1 ,sysobjsub91,11,8*28+19,158, 8,0       ;?? Description
dw 00,255*256+1 ,sysobjsubh0,01,8*29+19,158, 8,0       ;?? Description
dw 00,255*256+1 ,sysobjsubh1,11,8*30+19,158, 8,0       ;?? Description
dw 00,255*256+1 ,sysobjsubh2,11,8*31+19,158, 8,0       ;?? Description
dw 00,255*256+1 ,sysobjsub60,01,8*32+19,158, 8,0       ;?? Description
dw 00,255*256+1 ,sysobjsub61,11,8*33+19,158, 8,0       ;?? Description
dw 00,255*256+1 ,sysobjsub70,01,8*34+19,158, 8,0       ;?? Description
dw 00,255*256+1 ,sysobjsub71,11,8*35+19,158, 8,0       ;?? Description
dw 00,255*256+1 ,sysobjsub80,01,8*36+19,158, 8,0       ;?? Description
dw 00,255*256+1 ,sysobjsub81,11,8*37+19,158, 8,0       ;?? Description
dw 00,255*256+1 ,sysobjsube0,01,8*38+19,158, 8,0       ;?? Description
dw 00,255*256+1 ,sysobjsube1,11,8*39+19,158, 8,0       ;?? Description
dw 00,255*256+1 ,sysobjsubi0,01,8*40+19,158, 8,0       ;?? Description
dw 00,255*256+1 ,sysobjsubi1,11,8*41+19,158, 8,0       ;?? Description
dw 00,255*256+1 ,sysobjsuba0,01,8*42+19,158, 8,0       ;?? Description
dw 00,255*256+1 ,sysobjsuba1,11,8*43+19,158, 8,0       ;?? Description

sysobjsub00 dw systxtsub00,4*1+0+512
sysobjsub10 dw systxtsub10,4*1+0
sysobjsub11 dw systxtsub11,4*3+0
sysobjsub12 dw systxtsub12,4*3+0
sysobjsubd0 dw systxtsubd0,4*1+0
sysobjsubd1 dw systxtsubd1,4*3+0
sysobjsubd2 dw systxtsubd2,4*3+0
sysobjsubc0 dw systxtsubc0,4*1+0
sysobjsubc1 dw systxtsubc1,4*3+0
sysobjsubc2 dw systxtsubc2,4*3+0
sysobjsub20 dw systxtsub20,4*1+0
sysobjsub21 dw systxtsub21,4*3+0
sysobjsub22 dw systxtsub22,4*3+0
sysobjsubf0 dw systxtsubf0,4*1+0
sysobjsubf1 dw systxtsubf1,4*3+0
sysobjsubg0 dw systxtsubg0,4*1+0
sysobjsubg1 dw systxtsubg1,4*3+0
sysobjsub30 dw systxtsub30,4*1+0
sysobjsub31 dw systxtsub31,4*3+0
sysobjsubb0 dw systxtsubb0,4*1+0
sysobjsubb1 dw systxtsubb1,4*3+0
sysobjsubj0 dw systxtsubj0,4*1+0
sysobjsubj1 dw systxtsubj1,4*3+0
sysobjsub40 dw systxtsub40,4*1+0+512
sysobjsubk0 dw systxtsubk0,4*1+0
sysobjsubk1 dw systxtsubk1,4*3+0
sysobjsubk2 dw systxtsubk2,4*3+0
sysobjsub90 dw systxtsub90,4*1+0
sysobjsub91 dw systxtsub91,4*3+0
sysobjsubh0 dw systxtsubh0,4*1+0
sysobjsubh1 dw systxtsubh1,4*3+0
sysobjsubh2 dw systxtsubh2,4*3+0
sysobjsub60 dw systxtsub60,4*1+0
sysobjsub61 dw systxtsub61,4*3+0
sysobjsub70 dw systxtsub70,4*1+0
sysobjsub71 dw systxtsub71,4*3+0
sysobjsub80 dw systxtsub80,4*1+0
sysobjsub81 dw systxtsub81,4*3+0
sysobjsube0 dw systxtsube0,4*1+0
sysobjsube1 dw systxtsube1,4*3+0
sysobjsubi0 dw systxtsubi0,4*1+0
sysobjsubi1 dw systxtsubi1,4*3+0
sysobjsuba0 dw systxtsuba0,4*1+0
sysobjsuba1 dw systxtsuba1,4*3+0

prgtrnend

relocate_table
relocate_end
