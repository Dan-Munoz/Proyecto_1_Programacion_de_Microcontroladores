/*
* Proyecto1_final.asm
*
* Creado: 28/02/2026 15:11:30
* Autor : Dan Muñoz
* Descripción: Proyecto 1 Programación de Microcontroladores
* Reloj digital de 4 displays de 7 segmentos, que muestran hora en formato 24hrs (00:00 - 23:59), fecha formato DIA DIA:MES MES (01:01 - 31:12)
* además de alarma, todo lo anteriormente mencionado configurable. El reloj consta de 8 modos 0-7 que se muestran a través de 3 leds (B1-B3) y
* la alarma activa un buzzer desactivable mediante cualquiera de los botones incremento/decremento, además
* los dos puntos de los displays se encienden/apagan cada 500ms.
*/
/******************************************************************************************************/
// Encabezado (Definición de Registros, Variables y Constantes)
.include "M328PDEF.inc"						// Include definitions specific to ATMega328P
.equ	TMR0_VALUE	=	6					// TCNT0
.equ	TMR1_VALUE	=	0x85EE				// TCNT1
.equ	MAX_MODES	=	8					// Limitar los modos a 8 (0-7)
.def	PUNTO		=	R25					// Registro para encender D7 (puntos del display)

.dseg
//variable_name:     .byte   1   // Memory alocation for variable_name:     .byte   (byte size)
// Variables en RAM
MULTIPLEXOR		:	.byte 1					// Para multiplexar displays
DISP_VALUE		:	.byte 1					// Valor que se mostrará en PORTD (display)
UN_MIN			:	.byte 1					// Unidades de minutos
DEC_MIN			:	.byte 1					// Decenas de minutos
UN_HORA			:	.byte 1					// Unidades de hora 
DEC_HORA		:	.byte 1					// Decenas de hora
UN_DIA			:	.byte 1					// Unidades de día
DEC_DIA			:	.byte 1					// Decenas de día
UN_MES			:	.byte 1					// Unidades de mes
DEC_MES			:	.byte 1					// Decenas de mes
TIEMPO			:	.byte 1					// Contador de 0-120 para timer 1 para esperar 1 minuto
ESTADO			:	.byte 1					// Estado de pines C4 y C5 (botones incremento y decremento)
											  
MODE			:	.byte 1					// Modo actual
CONTAR			:	.byte 1					// Bandera para contar minutos
MULTIPLEXION	:	.byte 1					// Bandera para cambiar la multiplexion de los displays
INCREMENTAR		:	.byte 1					// Bandera para incrementar dependiendo el modo
DECREMENTAR		:	.byte 1					// Bandera para decrementar dependiendo el modo
UN_MIN_ALARMA	:	.byte 1					// Unidades de minutos de alarma
DEC_MIN_ALARMA	:	.byte 1					// Decenas de minutos de alarma
UN_HORA_ALARMA	:	.byte 1					// Unidades de hora de alarma
DEC_HORA_ALARMA	:	.byte 1					// Decenas de hora de alarma
ALARMA			:	.byte 1					// Bandera para activar el buzzer

.cseg
.org 0x0000									// Vector de inicio
	JMP START								
.org PCI0addr								// Vector de interrupción pin change pin B0
	JMP PINB_ISR							
.org PCI1addr								// Vector de interrupción pin change pin C4-C5
	JMP PINC_ISR							
.org OVF1addr								// Vector de interrupción overflow timer 1
	JMP TMR1_ISR							
.org OVF0addr								// Vector de interrupción overflow timer 0
	JMP TMR0_ISR

 /*****************************************************************************************************/
// Configuración de la pila
	LDI     R16, LOW(RAMEND)
	OUT     SPL, R16
	LDI     R16, HIGH(RAMEND)
	OUT     SPH, R16

// Tabla de valores Display 7 segmentos (0-F)
table7seg: .DB 0x3F,0x06,0x5B,0x4F,0x66,0x6D,0x7D,0x07,0x7F,0x6F,0x77,0x7C,0x39,0x5E,0x79,0x71

/******************************************************************************************************/
// Configuracion MCU
START:
	// Disable interruptions
	CLI
	// Define Entradas y Salidas
	// Puerto B
	LDI	R16, (1 << DDB1) | (1 << DDB2) | (1 << DDB3) | (1 << DDB5)
	OUT	DDRB, R16							// B0 botón, B1-B3 leds de modo y B5 buzzer
	LDI	R16, (1 << PB0)
	OUT	PORTB, R16							// Pullup en B0
	// Puerto C
	LDI R16, (1 << DDC0) | (1 << DDC1) | (1 << DDC2) | (1 << DDC3)
	OUT DDRC, R16							// C0-C3 para multiplexar displays y C4-C5 para
	LDI R16, 0xFF							// botones incremento/decremento
	OUT PORTC, R16							// Pullup en C4-C5
	// Puerto D
	LDI R16, 0xFF
	OUT DDRD, R16							// D0-D7 para mostrar valores de displays
	CLR R16
	OUT PORTD, R16
	// Apagar UART RX/TX
	LDI  R16, 0x00
    STS  UCSR0B, R16 	

	// Inicialización de timers
	CALL	INIT_TMR1
	CALL	INIT_TMR0

	// Limpiar registros y cargar variables
	CLR	PUNTO
	LDI R16, 0b00001110						// Cargar valor para multiplexar diplay 0
	STS MULTIPLEXOR, R16
	
	// Guardar 00 en minutos y horas
	LDI R16, 0x00
	STS UN_MIN, R16
	STS DEC_MIN, R16
	STS UN_HORA, R16
	STS DEC_HORA, R16
	STS DEC_DIA, R16
	STS DEC_MES, R16
	STS DISP_VALUE, R16
	// Configurar alarma para 00:00 por default
	STS	UN_MIN_ALARMA, R16	
	STS	DEC_MIN_ALARMA, R16
	STS	UN_HORA_ALARMA, R16
	STS	DEC_HORA_ALARMA, R16

	STS	CONTAR, R16							// Apagar bandera para incrementar minutos
	STS MODE, R16							// Iniciar en modo 0
	STS	MULTIPLEXION, R16					// Apagar bandera para multiplexar
	STS	INCREMENTAR, R16					// Apagar bandera para incrementar
	STS	DECREMENTAR, R16					// Apagar bandera para decrementar
	// Guardar fecha en 01:01
	LDI	R16, 0X01
	STS UN_DIA, R16
	STS UN_MES, R16
	// Leer C4-C5 y guardarlos en ESTADO
	IN R16, PINC							           
    ANDI R16, 0b00110000
    STS ESTADO, R16

	// Habilitar interrupciones
	// Timer 1
	LDI		R16, (1 << TOIE1)
	STS		TIMSK1, R16
	// Timer 0
	LDI		R16, (1 << TOIE0)
	STS		TIMSK0, R16
	// PC4(INCREMENTAR) y PC5(DECREMENTAR)
	LDI		R16, (1 << PCIE1) | (1 << PCIE0)
	STS		PCICR, R16
	LDI		R16, (1 << PCINT12) | (1 << PCINT13)
	STS		PCMSK1, R16
	// PB5 (MODO)
	LDI		R16, (1 << PCINT0)
	STS		PCMSK0, R16
	CLR		R16
	SEI
	
/*************************************************** LOOP ***********************************************/
/* Revisa el modo seleccionado y salta a la subrutina correspondiente, pasa a la subrutina
* de multiplexación, muestra el valor en el display seleccionado, revisa si la alarma
* está activada y muestra el modo actual en los leds.
*/
MAIN_LOOP:
// Verificar modo actual
VERIFY_MODE0:
	LDS		R16, MODE
	CPI		R16, 0x00
	BRNE	VERIFY_MODE1					
	RJMP	MODE_0							// Saltar a subrutina de modo 0
VERIFY_MODE1:
	CPI		R16, 0x01
	BRNE	VERIFY_MODE2
	RJMP	MODE_1							// Saltar a subrutina de modo 1
VERIFY_MODE2:
	CPI		R16, 0x02
	BRNE	VERIFY_MODE3
	RJMP	MODE_2							// Saltar a subrutina de modo 2
VERIFY_MODE3:
	CPI		R16, 0x03
	BRNE	VERIFY_MODE4
	RJMP	MODE_3							// Saltar a subrutina de modo 3
VERIFY_MODE4:
	CPI		R16, 0x04
	BRNE	VERIFY_MODE5
	RJMP	MODE_4							// Saltar a subrutina de modo 4
VERIFY_MODE5:
	CPI		R16, 0x05
	BRNE	VERIFY_MODE6
	RJMP	MODE_5							// Saltar a subrutina de modo 5
VERIFY_MODE6:
	CPI		R16, 0x06
	BRNE	VERIFY_MODE7
	RJMP	MODE_6							// Saltar a subrutina de modo 6
VERIFY_MODE7:
	CPI		R16, 0x07
	BRNE	MULTIPLEXAR
	RJMP	MODE_7							// Saltar a subrutina de modo 7

MULTIPLEXAR:
	RJMP	MULTIPLEXACION					// Saltar a subrutina de multiplexación

MOSTRAR:
	LDS		R16, MULTIPLEXOR
	ORI		R16, 0b00110000
	OUT		PORTC, R16						// Encender display correspondiente

	LDS		R16, DISP_VALUE					// Bajar a R16 el valor del display
	LDI		ZH, HIGH(table7seg<<1)			// Ubicarse en el primer valor de la tabla
	LDI		ZL, LOW(table7seg<<1)	
	ADD		ZL, R16							// Sumamos a la dirección 0 de la tabla el valor del display
	LPM		R17, Z							// Bajamos el valor de la tabla a R17
	OR		R17, PUNTO						// Encendemos/apagamos dos puntos
	OUT		PORTD, R17						// Mostramos valor en display

	// Verificar si bandera ALARMA está encendida y mostrar modo
	LDS		R16, MODE
	LSL		R16
	ORI		R16, 0x01
	LDS		R17, ALARMA
	CPI		R17, 0x01
	BRNE	MOSTRAR_MODO
	ORI		R16, 0b00100000					// Si ALARMA = 0x01 encender buzzer

MOSTRAR_MODO:
	OUT		PORTB, R16						// Mostrar modo actual en leds

    RJMP    MAIN_LOOP


/*********************************************** MODOS **************************************************/

/*********************************************** MODO_0 ************************************************/
/* Revisa si el timer 1 ya encendió la bandera CONTAR para incrementar minutos, si sí, incrementa
* minutos y horas (00:00 - 23:59), y al llegar a 00:00 aumentar días y meses (01:01 - 31:12).
*/
MODE_0:
	CLI										// Desactivar interrupciones momentáneamente para poder apagar bandera
	LDS		R16, CONTAR
	CPI		R16, 0x01						// Revisar si CONTAR = 1 para incrementar hora
	BRNE	NO_INCREMENTO
	// Limpiar variable CONTAR
	CLR		R16
	STS		CONTAR, R16						// Limpiar bandera contar
	SEI
	RJMP	CARGAR_VALORES
NO_INCREMENTO:								// Salir de subrutina de modo
	SEI
	RJMP	EXIT_CONTAR_TIEMPO
CARGAR_VALORES:
// Cargar valores de hora y fecha en registros de propósito general
	LDS		R17, UN_MIN
	LDS		R18, DEC_MIN
	LDS		R19, UN_HORA
	LDS		R20, DEC_HORA
	LDS		R21, UN_DIA
	LDS		R22, DEC_DIA
	LDS		R23, UN_MES
	LDS		R24, DEC_MES

	INC		R17								// Incrementar unidades de minutos
	CPI		R17, 10							// Si ya pasaron 10 minutos incrementar decenas de minutos
	BREQ	SUMAR_DEC_MIN	
	RJMP	GUARDAR_TMR1_ISR
SUMAR_DEC_MIN:
	CLR		R17								// Limpiar unidades de  minutos
	INC		R18								// Incrementar decenas de minutos
	CPI		R18, 6							// Si ya pasaron 60 minutos incrementar unidades de hora
	BREQ	SUMAR_UN_HORA
	RJMP	GUARDAR_TMR1_ISR
SUMAR_UN_HORA:								
	CLR		R18								// Limpiar decenas de minutos
	INC		R19								// Incrementar unidades de hora
	CPI		R19, 4							// Si unidades de hora = 4 ir a rutina de verificación cambio de dia
	BREQ	VERIFY_CAMBIO_DIA
	CPI		R19, 10							// Si ya pasaron 10 horas incrementar decenas de hora
	BREQ	SUMAR_DEC_HORA
	RJMP	GUARDAR_TMR1_ISR
SUMAR_DEC_HORA:
	CLR		R19								// Limpiar unidades de hora
	INC		R20								// Incrementar decenas de hora
VERIFY_CAMBIO_DIA:
// Rutina para verificar cambio de día
	CPI		R19, 4
	BREQ	COMPARAR_DEC_HORA
	RJMP	GUARDAR_TMR1_ISR
COMPARAR_DEC_HORA:
	CPI		R20, 2
	BREQ	LIMPIAR_HORA
	RJMP	GUARDAR_TMR1_ISR
LIMPIAR_HORA:								// Si decenas de hora = 2 y unidades de hora = 4 cambiar de dia
	CLR		R19								// Limpiar unidades de hora
	CLR		R20								// Limpiar decenas de hora

	CPI		R24, 1							// Revisar decenas de meses para revisar 3 meses primeros o 9 finales
	BREQ	TRES_MESES_FINALES
	RJMP	NUEVE_MESES_PRIMEROS

TRES_MESES_FINALES:
	CPI		R23, 1							// Si es noviembre saltar a rutina de 30 días, si no saltar a 31 días
	BREQ	TREINTA_DIAS
	RJMP	TREINTA_Y_UN_DIAS

NUEVE_MESES_PRIMEROS:
	CPI		R23, 2							// Si es febrero saltar a rutina de 28 días
	BREQ	VEINTIOCHO_DIAS
	CPI		R23, 4							// Si es abril saltar a rutina de 30 días
	BREQ	TREINTA_DIAS
	CPI		R23, 6							// Si es junio saltar a rutina de 30 días
	BREQ	TREINTA_DIAS
	CPI		R23, 9							// Si es septiembre saltar a rutina de 30 días
	BREQ	TREINTA_DIAS
	RJMP	TREINTA_Y_UN_DIAS				// Resto de meses 1x saltar a rutina de 31 días

/* Rutina que aumenta día hasta 28 y luego aumenta mes*/
VEINTIOCHO_DIAS:
	INC		R21
	CPI		R21, 9							// Si la unidad de día incrementó a 9 verificar si ya llego a 29 para cambiar mes
	BREQ	VERIFY_CAMBIO_MES3
	CPI		R21, 10							// Aumentar decena de día
	BRNE	GUARDAR_TMR1_ISR
	CLR		R21
	INC		R22
// Revisar si día incrementó a 29 para limpiar a 01 y cambiar mes
VERIFY_CAMBIO_MES3:
	CPI		R21, 9
	BRNE	GUARDAR_TMR1_ISR
	CPI		R22, 2
	BRNE	GUARDAR_TMR1_ISR
	LDI		R21, 0x01
	CLR		R22
	RJMP	CAMBIO_MES

/* Rutina que aumenta día hasta 31 y luego aumenta mes*/
TREINTA_Y_UN_DIAS:
	INC		R21
	CPI		R21, 2							// Si la unidad de día aumentó a 2 revisar si llegó a 32 para cambiar mes
	BREQ	VERIFY_CAMBIO_MES2
	CPI		R21, 10							// Aumentar decena de día
	BRNE	GUARDAR_TMR1_ISR
	CLR		R21
	INC		R22
// Revisar si día incrementó a 32 para reiniciar a 01 y aumentar mes
VERIFY_CAMBIO_MES2:
	CPI		R21, 2
	BRNE	GUARDAR_TMR1_ISR
	CPI		R22, 3
	BRNE	GUARDAR_TMR1_ISR
	LDI		R21, 0x01
	CLR		R22
	RJMP	CAMBIO_MES

/* Rutina que aumenta día hasta 30 y luego aumenta mes*/
TREINTA_DIAS:
	INC		R21
	CPI		R21, 1							// Si la unidad de día aumentó a 1 revisar si llegó a 31 para cambiar de mes
	BREQ	VERIFY_CAMBIO_MES1
	CPI		R21, 10							// Aumentar decena de día
	BRNE	GUARDAR_TMR1_ISR
	CLR		R21
	INC		R22
// Revisar si día incrementó a 31 para reiniciar a 01 y aumentar mes
VERIFY_CAMBIO_MES1:
	CPI		R21, 1
	BRNE	GUARDAR_TMR1_ISR
	CPI		R22, 3
	BRNE	GUARDAR_TMR1_ISR
	LDI		R21, 0x01
	CLR		R22
	RJMP	CAMBIO_MES

/* Aumento de mes con overflow cuando llega a 13 (01-12)*/
CAMBIO_MES:
	INC		R23
	CPI		R23, 3
	BREQ	VERIFY_DICIEMBRE
	CPI		R23, 10
	BRNE	GUARDAR_TMR1_ISR
	CLR		R23
	INC		R24
VERIFY_DICIEMBRE:
	CPI		R23, 3
	BRNE	GUARDAR_TMR1_ISR
	CPI		R24, 1
	BRNE	GUARDAR_TMR1_ISR
	LDI		R23, 1
	CLR		R24
	RJMP	GUARDAR_TMR1_ISR

/* Guardar los valores de minutos, horas, día y mes en las variables*/
GUARDAR_TMR1_ISR:
	STS		UN_MIN, R17
	STS		DEC_MIN, R18
	STS		UN_HORA, R19
	STS		DEC_HORA, R20
	STS		UN_DIA, R21
	STS		DEC_DIA, R22
	STS		UN_MES, R23
	STS		DEC_MES, R24

/* Verificar si la hora configurada de la alarma coincide con la hora actual*/
ALARMA_Y_MODO:
	// Cargar variables a registros de propósito general
	LDS		R16, UN_MIN
	LDS		R17, UN_MIN_ALARMA
	LDS		R18, DEC_MIN
	LDS		R19, DEC_MIN_ALARMA
	LDS		R20, UN_HORA
	LDS		R21, UN_HORA_ALARMA
	LDS		R22, DEC_HORA
	LDS		R23, DEC_HORA_ALARMA
	// Revisar si cada valor coincide
	CP		R16, R17
	BRNE	EXIT_CONTAR_TIEMPO
	CP		R18, R19
	BRNE	EXIT_CONTAR_TIEMPO
	CP		R20, R21
	BRNE	EXIT_CONTAR_TIEMPO
	CP		R22, R23
	BRNE	EXIT_CONTAR_TIEMPO
	// Si minutos y horas coinciden guardar 1 en alarma
	LDI		R16, 0x01
	STS		ALARMA, R16

/* Revisar si la variable bandera de los botones incremento y decremento está en 1 para cargar 0 a alarma */
EXIT_CONTAR_TIEMPO:
	CLI
	// Revisar botón 1
	LDS		R16, INCREMENTAR
	CPI		R16, 0x01
	BRNE	NO_BOTON1_MODE0	
	// Limpiar bandera INCREMENTAR
	CLR		R16
	STS		INCREMENTAR, R16
	SEI
	RJMP	APAGAR_ALARMA_MODE0
NO_BOTON1_MODE0:
	SEI
	CLI
	// Revisar botón 2
	LDS		R16, DECREMENTAR
	CPI		R16, 0x01
	BRNE	NO_BOTON2_MODE0
	// Limpiar bandera DECREMENTAR
	CLR		R16
	STS		DECREMENTAR, R16
	SEI
	RJMP	APAGAR_ALARMA_MODE0
// Si ninguno está presionado salir
NO_BOTON2_MODE0:
	SEI
	RJMP	EXIT_MODE_0
// Si algún botón está presionado cargar 0 a variable ALARMA
APAGAR_ALARMA_MODE0:
	LDI		R16, 0x00
	STS		ALARMA, R16
/* Salida del modo */
EXIT_MODE_0:
	RJMP	MULTIPLEXAR


/************************************************* MODO_1 ***********************************************/
/* Modo que muestra fecha, pero la función es la misma que el modo 0 (aumentar hora), por lo que se salta a la
subrutina de MODE_0 para que siga aumentando el tiempo */
MODE_1:
	// Salto a MODE_0 para segir contando
	RJMP	MODE_0


/************************************************* MODO_2 ***********************************************/
/* Modo encargado de modificar minutos, revisa si las banderas (variables) incrementar o decrementar
están encendidas para incrementar o decrementar minutos */
MODE_2:
	CLI
	// Revisar si INCREMENTAR = 1
	LDS		R16, INCREMENTAR
	CPI		R16, 0x01
	BRNE	NO_INCREMENTAR_MIN	
	// Limpiar bandera
	CLR		R16
	STS		INCREMENTAR, R16
	SEI
	RJMP	INCREMENTAR_MIN
NO_INCREMENTAR_MIN:
	SEI
	CLI
	// Revisar si DECREMENTAR = 1
	LDS		R16, DECREMENTAR
	CPI		R16, 0x01
	BRNE	NO_DECREMENTAR_MIN
	// Limpiar bandera
	CLR		R16
	STS		DECREMENTAR, R16
	SEI
	RJMP	DECREMENTAR_MIN
// Si ninguna bandera de botón está encendida salir del modo
NO_DECREMENTAR_MIN:
	SEI
	RJMP	EXIT_MODE_2

/* Incrementar minutos*/
INCREMENTAR_MIN:
	// Cargar variables de minutos a registros de propósito general
	LDS		R17, UN_MIN
	LDS		R18, DEC_MIN
	INC		R17								// Incrementar unidades de minutos
	CPI		R17, 10							// Aumentar decenas de minutos
	BRNE	GUARDAR_INC_MIN
	CLR		R17
	INC		R18
	CPI		R18, 6							// Si llegó a 60 resetear
	BRNE	GUARDAR_INC_MIN
	CLR		R18
GUARDAR_INC_MIN:
	// Guardar valores de minutos
	STS		UN_MIN, R17
	STS		DEC_MIN, R18
	RJMP	EXIT_MODE_2

/* Decrementar minutos */
DECREMENTAR_MIN:
	// Cargar valores de minutos a registros de propósito general
	LDS		R17, UN_MIN
	LDS		R18, DEC_MIN
	DEC		R17								// Decrementar unidades de minutos
	CPI		R17, 255						// Decrementar decenas de minutos
	BRNE	GUARDAR_DEC_MIN
	LDI		R17, 9
	DEC		R18
	CPI		R18, 255						// Si llegó a 00 resetear
	BRNE	GUARDAR_DEC_MIN
	LDI		R18, 5
GUARDAR_DEC_MIN:
	// Guardar valores de minutos
	STS		UN_MIN, R17
	STS		DEC_MIN, R18

/* Salida Modo 2 */
EXIT_MODE_2:
	RJMP	MULTIPLEXAR


/************************************************** MODO_3 ***********************************************/
/* Modo encargado de modificar horas, según esté encendida la bandera INCREMENTAR o DECREMENTAR */
MODE_3:
	CLI
	// Revisar si INCREMENTAR = 1
	LDS		R16, INCREMENTAR
	CPI		R16, 0x01
	BRNE	NO_INCREMENTAR_HORA	
	// Limpiar bandera
	CLR		R16
	STS		INCREMENTAR, R16
	SEI
	RJMP	INCREMENTAR_HORA
NO_INCREMENTAR_HORA:
	SEI
	CLI
	// Revisar si DECREMENTAR = 1
	LDS		R16, DECREMENTAR
	CPI		R16, 0x01
	BRNE	NO_DECREMENTAR_HORA	
	// Limpiar bandera
	CLR		R16
	STS		DECREMENTAR, R16
	SEI
	RJMP	DECREMENTAR_HORA
// Si no está encendida ninguna bandera, salir
NO_DECREMENTAR_HORA:
	SEI
	RJMP	EXIT_MODE_3

/* Incrementar hora */
INCREMENTAR_HORA:
	// Cargar valores de hora en registros de propósito general
	LDS		R17, UN_HORA
	LDS		R18, DEC_HORA
	INC		R17								// Incrementar unidades de hora
	CPI		R17, 4							// Si unidades de hora incrementó a 4 revisar si llegó a 24
	BREQ	VERIFY_24HRS
	CPI		R17, 10							// Incrementar decenas de hora
	BREQ	INCREMENTAR_DEC_HORA
	RJMP	GUARDAR_INC_HORA
INCREMENTAR_DEC_HORA:
	CLR		R17
	INC		R18
// Revisar si horas = 24 para reiniciar hora
VERIFY_24HRS:
	CPI		R17, 4
	BREQ	COMPARAR_DEC_HORA_INC
	RJMP	GUARDAR_INC_HORA
COMPARAR_DEC_HORA_INC:
	CPI		R18, 2
	BREQ	LIMPIAR_HORA_INC
	RJMP	GUARDAR_INC_HORA
// Al llegar a 24:00 reiniciar hora (00:00)
LIMPIAR_HORA_INC:
	CLR		R17
	CLR		R18
// Guardar valores de hora
GUARDAR_INC_HORA:
	STS		UN_HORA, R17
	STS		DEC_HORA, R18
	RJMP	EXIT_MODE_3

/* Si está encendida la bandera de decrementar, decrementar hora hasta 00:00 y luego pasar a 23:59 */
DECREMENTAR_HORA:
	// Cargar valores de hora a registros de propósito general
	LDS		R17, UN_HORA
	LDS		R18, DEC_HORA
	DEC		R17								// Decrementar unidades de hora
	CPI		R17, 255						// Si unidades de hora = 0 decrementar decenas de hora
	BREQ	DECREMENTAR_DEC_HORA
	RJMP	GUARDAR_DEC_HORA
DECREMENTAR_DEC_HORA:
	LDI		R17, 9
	DEC		R18								// Decrementar decenas de hora
	CPI		R18, 255						// Si unidades de hora = 0 reiniciar hora
	BREQ	LIMPIAR_HORA_DEC
	RJMP	GUARDAR_DEC_HORA
// Reiniciar hora (23:59)
LIMPIAR_HORA_DEC:
	LDI		R17, 3
	LDI		R18, 2
// Guardar valores de hora
GUARDAR_DEC_HORA:
	STS		UN_HORA, R17
	STS		DEC_HORA, R18
	RJMP	EXIT_MODE_3
	
EXIT_MODE_3:
	RJMP	MULTIPLEXAR


/************************************************* MODO_4 ************************************************/
/* Modo encargado de modificar meses según la bandera de botón activada (si se modifica el mes se
 resetea el día a 01) */
MODE_4:
	CLI
	// Revisar si bandera Incrementar = 1
	LDS		R16, INCREMENTAR
	CPI		R16, 0x01
	BRNE	NO_INCREMENTAR_MES	
	// Limpiar bandera
	CLR		R16
	STS		INCREMENTAR, R16
	SEI
	RJMP	INCREMENTAR_MES
NO_INCREMENTAR_MES:
	SEI
	CLI
	// Revisar si bandera Decrementar = 1
	LDS		R16, DECREMENTAR
	CPI		R16, 0x01
	BRNE	NO_DECREMENTAR_MES	
	// Limpiar bandera
	CLR		R16
	STS		DECREMENTAR, R16
	SEI
	RJMP	DECREMENTAR_MES
// Si ambas banderas son 0 salir
NO_DECREMENTAR_MES:
	SEI
	RJMP	EXIT_MODE_4

/* Incrementar mes */
INCREMENTAR_MES:
	// Cargar valores de mes y día
	LDS		R19, UN_DIA						
	LDI		R19, 0x01						// Cargar 01 a día
	LDS		R20, DEC_DIA					
	CLR		R20								
	LDS		R17, UN_MES
	LDS		R18, DEC_MES
	INC		R17								// Incrementar unidades de mes
	CPI		R17, 3							// Si un_mes incrementó a 3 revisar si ya se pasó de 12 para reiniciar
	BREQ	VERIFY_MES12
	CPI		R17, 10							// Si un_mes incrementó a 10 poner 0 y aumentar dec_mes
	BREQ	INCREMENTAR_DEC_MES
	RJMP	GUARDAR_INC_MES
INCREMENTAR_DEC_MES:
	CLR		R17
	INC		R18								// Incrementar dec_mes
// Revisar si mes llegó a 13 para reiniciar a 01
VERIFY_MES12:
	CPI		R17, 3
	BREQ	COMPARAR_DEC_MES_INC
	RJMP	GUARDAR_INC_MES
COMPARAR_DEC_MES_INC:
	CPI		R18, 1
	BREQ	LIMPIAR_MES_INC
	RJMP	GUARDAR_INC_MES
LIMPIAR_MES_INC:
	LDI		R17, 0x01						// Cargar mes 01
	CLR		R18
GUARDAR_INC_MES:
	// Guardar valores de mes y día
	STS		UN_DIA, R19						
	STS		DEC_DIA, R20					
	STS		UN_MES, R17
	STS		DEC_MES, R18
	RJMP	EXIT_MODE_4

/* Decrementar mes */
DECREMENTAR_MES:
	// Cargar valores de mes y día
	LDS		R19, UN_DIA						// Cargar 01 a día
	LDI		R19, 0x01						
	LDS		R20, DEC_DIA					
	CLR		R20								
    LDS  R17, UN_MES
    LDS  R18, DEC_MES

    // Si mes llegó a 01 siguiente es 12
    CPI  R17, 1
    BRNE NORMAL_DEC_CHECK
    CPI  R18, 0
    BRNE NORMAL_DEC_CHECK

    // Cargar 12
    LDI  R17, 2
    LDI  R18, 1
    RJMP GUARDAR_DEC_MES

NORMAL_DEC_CHECK:
    DEC  R17								// Decrementar un_mes
    CPI  R17, 255							// Si un_mes llegó a 0 cargar 9 y decrementar dec_mes
    BRNE GUARDAR_DEC_MES

    LDI  R17, 9
    DEC  R18								// Decrementar dec_mes

GUARDAR_DEC_MES:
	// Guardar valores de día y mes
	STS	 UN_DIA, R19						
	STS	 DEC_DIA, R20					
    STS  UN_MES, R17
    STS  DEC_MES, R18
    RJMP EXIT_MODE_4
	
EXIT_MODE_4:
	RJMP	MULTIPLEXAR


/************************************************** MODO_5 ************************************************/
/* Modo encargado de modificar día del mes actual según la bandera incrementar o decrementar */
MODE_5:
	CLI
	// Revisar si bandera Incrementar = 1
	LDS		R16, INCREMENTAR
	CPI		R16, 0x01
	BRNE	NO_INCREMENTAR_DIA	
	// Limpiar bandera
	CLR		R16
	STS		INCREMENTAR, R16
	SEI
	RJMP	INCREMENTAR_DIA
NO_INCREMENTAR_DIA:
	SEI
	CLI
	// Revisar si bandera Decrementar = 1
	LDS		R16, DECREMENTAR
	CPI		R16, 0x01
	BRNE	NO_DECREMENTAR_DIA
	// Limpiar bandera
	CLR		R16
	STS		DECREMENTAR, R16
	SEI
	RJMP	DECREMENTAR_DIA
// Si ninguna bandera está encendida, salir
NO_DECREMENTAR_DIA:
	SEI
	RJMP	EXIT_MODE_5

/* Incrementar día */
INCREMENTAR_DIA:
	// Cargar valores de mes y día a registros de propósito general
	LDS		R16, UN_DIA
	LDS		R17, DEC_DIA
	LDS		R18, UN_MES
	LDS		R19, DEC_MES

	// Revisar si dec_mes = 1 para saber si son los primeros 9 meses o los últimos 3
	CPI		R19, 1
	BREQ	TRES_MESES_FINALES_INC_DIA
	RJMP	NUEVE_MESES_PRIMEROS_INC_DIA

// Revisar 3 meses finales
TRES_MESES_FINALES_INC_DIA:
	CPI		R18, 1
	BREQ	TREINTA_DIAS_INC_DIA			// Si es nov ir a subrutina de 30 días
	RJMP	TREINTA_Y_UN_DIAS_INC_DIA		// Los otros ir a subrutina de 31 días

// Revisar 9 meses primeros
NUEVE_MESES_PRIMEROS_INC_DIA:
	CPI		R18, 2
	BREQ	VEINTIOCHO_DIAS_INC_DIA			// Si es feb ir a subrutina de 28 días
	CPI		R18, 4
	BREQ	TREINTA_DIAS_INC_DIA			// Si es abr ir a subrutina de 30 días
	CPI		R18, 6	
	BREQ	TREINTA_DIAS_INC_DIA			// Si es jun ir a subrutina de 30 días
	CPI		R18, 9
	BREQ	TREINTA_DIAS_INC_DIA			// Si es sept ir a subrutina de 30 días
	RJMP	TREINTA_Y_UN_DIAS_INC_DIA		// El resto ir a subrutina de 31 días

// Subrutina de 28 días de límite
VEINTIOCHO_DIAS_INC_DIA:
	INC		R16
	CPI		R16, 9
	BREQ	VERIFY_CAMBIO_MES3_INC_DIA
	CPI		R16, 10
	BRNE	GUARDAR_INC_DIA
	CLR		R16
	INC		R17
// Revisar si incrementó a 29 para reiniciar
VERIFY_CAMBIO_MES3_INC_DIA:
	CPI		R16, 9
	BRNE	GUARDAR_INC_DIA
	CPI		R17, 2
	BRNE	GUARDAR_INC_DIA
	LDI		R16, 0x01
	CLR		R17
	RJMP	GUARDAR_INC_DIA

// Subrutina de 31 días de límite
TREINTA_Y_UN_DIAS_INC_DIA:
	INC		R16
	CPI		R16, 2
	BREQ	VERIFY_CAMBIO_MES2_INC_DIA
	CPI		R16, 10
	BRNE	GUARDAR_INC_DIA
	CLR		R16
	INC		R17
// Si incrementó a 32 reiniciar
VERIFY_CAMBIO_MES2_INC_DIA:
	CPI		R16, 2
	BRNE	GUARDAR_INC_DIA
	CPI		R17, 3
	BRNE	GUARDAR_INC_DIA
	LDI		R16, 0x01
	CLR		R17
	RJMP	GUARDAR_INC_DIA

// Subrutina de 30 días de límite
TREINTA_DIAS_INC_DIA:
	INC		R16
	CPI		R16, 1
	BREQ	VERIFY_CAMBIO_MES1_INC_DIA
	CPI		R16, 10
	BRNE	GUARDAR_INC_DIA
	CLR		R16
	INC		R17
// Si incrementó a 31 reiniciar
VERIFY_CAMBIO_MES1_INC_DIA:
	CPI		R16, 1
	BRNE	GUARDAR_INC_DIA
	CPI		R17, 3
	BRNE	GUARDAR_INC_DIA
	LDI		R16, 0x01
	CLR		R17
	RJMP	GUARDAR_INC_DIA

GUARDAR_INC_DIA:
	// Guardar valores
	STS		UN_DIA, R16
	STS		DEC_DIA, R17
	STS		UN_MES, R18
	STS		DEC_MES, R19
	RJMP EXIT_MODE_5

/* Decrementar día con underflow correspondiente al mes */
DECREMENTAR_DIA:
    LDS     R16, UN_DIA
    LDS     R17, DEC_DIA
    LDS     R18, UN_MES
    LDS     R19, DEC_MES

    // Si no ha llegado a 01 solo decrementar hasta llegar a 01
    CPI     R16, 1
    BRNE    NORMAL_DEC_DIA
    CPI     R17, 0
    BRNE    NORMAL_DEC_DIA

	// Si ya llegó a 01 revisar el mes para hacer underflow correspondiente
    CPI     R19, 1
    BREQ    TRES_MESES_FINALES_DEC_DIA		// Revisar 9 primeros meses
    RJMP    NUEVE_MESES_PRIMEROS_DEC_DIA	// Revisar últimos 3 meses

// Revisar últimos 3 meses
TRES_MESES_FINALES_DEC_DIA:
    CPI     R18, 1
    BREQ    CARGAR_30						// Si es nov ir a subrutina de 30 días
    RJMP    CARGAR_31						// Los otros ir a subrutina de 31 días

// Revisar primeros 9 meses
NUEVE_MESES_PRIMEROS_DEC_DIA:
    CPI     R18, 2							
    BREQ    CARGAR_28						// Si es feb ir a subrutina de 28 días
    CPI     R18, 4
    BREQ    CARGAR_30						// Si es abr ir a subrutina de 30 días
    CPI     R18, 6
    BREQ    CARGAR_30						// Si es jun ir a subrutina de 30 días
    CPI     R18, 9
    BREQ    CARGAR_30						// Si es sept ir a subrutina de 30 días
    RJMP    CARGAR_31						// El resto ir a subrutina de 31 días

// Subrutina para cargar 28
CARGAR_28:
    LDI     R16, 8
    LDI     R17, 2
    RJMP    GUARDAR_DEC_DIA

// Subrutina para cargar 30
CARGAR_30:
    LDI     R16, 0
    LDI     R17, 3
    RJMP    GUARDAR_DEC_DIA

// Subrutina para cargar 31
CARGAR_31:
    LDI     R16, 1
    LDI     R17, 3
    RJMP    GUARDAR_DEC_DIA

// Decremento normal de día hasta llegar a 01
NORMAL_DEC_DIA:
    DEC     R16
    CPI     R16, 255
    BRNE    GUARDAR_DEC_DIA
    LDI     R16, 9
    DEC     R17

GUARDAR_DEC_DIA:
	// Guardar valores de día y mes
    STS     UN_DIA, R16
    STS     DEC_DIA, R17
    STS     UN_MES, R18
    STS     DEC_MES, R19
    RJMP    EXIT_MODE_5

EXIT_MODE_5:
	RJMP	MULTIPLEXAR


/************************************************* MODO_6 *************************************************/
/* Modificar valores de minutos de alarma según la bandera de incremento o decremento activada */
MODE_6:
	CLI
	// Revisar si Incrementar = 1
	LDS		R16, INCREMENTAR
	CPI		R16, 0x01
	BRNE	NO_INCREMENTAR_MIN_ALARMA	
	// Limpiar bandera
	CLR		R16
	STS		INCREMENTAR, R16
	SEI
	RJMP	INCREMENTAR_MIN_ALARMA
NO_INCREMENTAR_MIN_ALARMA:
	SEI
	CLI
	// Revisar si Decrementar = 1
	LDS		R16, DECREMENTAR
	CPI		R16, 0x01
	BRNE	NO_DECREMENTAR_MIN_ALARMA	
	// Limpiar bandera
	CLR		R16
	STS		DECREMENTAR, R16
	SEI
	RJMP	DECREMENTAR_MIN_ALARMA
// Si ninguna bandera está encendida, salir
NO_DECREMENTAR_MIN_ALARMA:
	SEI
	RJMP	EXIT_MODE_6

/* Incrementar minutos de alarma */
INCREMENTAR_MIN_ALARMA:
	// Cargar valores a registros
	LDS		R17, UN_MIN_ALARMA
	LDS		R18, DEC_MIN_ALARMA
	INC		R17								// Incrementar unidades de minutos
	CPI		R17, 10							// Si llegó a 10 incrementar decenas de minutos
	BRNE	GUARDAR_INC_MIN_ALARMA
	CLR		R17
	INC		R18								// Incrementar decenas de minutos
	CPI		R18, 6							// Si llegó a 6 reiniciar
	BRNE	GUARDAR_INC_MIN_ALARMA
	CLR		R18
// Guardar valores y salir
GUARDAR_INC_MIN_ALARMA:
	STS		UN_MIN_ALARMA, R17
	STS		DEC_MIN_ALARMA, R18
	RJMP	EXIT_MODE_6

/* Decrementar minutos de alarma */
DECREMENTAR_MIN_ALARMA:
	// Cargar valores a registros
	LDS		R17, UN_MIN_ALARMA
	LDS		R18, DEC_MIN_ALARMA
	DEC		R17								// Decrementar unidades de minutos
	CPI		R17, 255						// Si llegó a 0 cargar 9 y restar dec de minutos
	BRNE	GUARDAR_DEC_MIN_ALARMA
	LDI		R17, 9
	DEC		R18								// Decrementar decenas de minutos
	CPI		R18, 255
	BRNE	GUARDAR_DEC_MIN_ALARMA
	LDI		R18, 5							// Si llegó a 0 cargar 5

// Guardar valores
GUARDAR_DEC_MIN_ALARMA:
	STS		UN_MIN_ALARMA, R17
	STS		DEC_MIN_ALARMA, R18
	
EXIT_MODE_6:
	RJMP	MULTIPLEXAR


/************************************************* MODO_7 ************************************************/
/* Modo encargado de modificar las horas de alarma según está encendida incrementar o decrementar */
MODE_7:
	CLI
	// Revisar si Incrementar = 1
	LDS		R16, INCREMENTAR
	CPI		R16, 0x01
	BRNE	NO_INCREMENTAR_HORA_ALARMA
	// Limpiar bandera
	CLR		R16
	STS		INCREMENTAR, R16
	SEI
	RJMP	INCREMENTAR_HORA_ALARMA
NO_INCREMENTAR_HORA_ALARMA:
	SEI
	CLI
	// Revisar si Decrementar = 1
	LDS		R16, DECREMENTAR
	CPI		R16, 0x01
	BRNE	NO_DECREMENTAR_HORA_ALARMA
	// Limpiar bandera
	CLR		R16
	STS		DECREMENTAR, R16
	SEI
	RJMP	DECREMENTAR_HORA_ALARMA
// Si ninguna bandera 
NO_DECREMENTAR_HORA_ALARMA:
	SEI
	RJMP	EXIT_MODE_7

/* Incrementar hora de alarma */
INCREMENTAR_HORA_ALARMA:
	// Cargar valores de hora de alarma a registros
	LDS		R17, UN_HORA_ALARMA
	LDS		R18, DEC_HORA_ALARMA
	INC		R17								// Incrementar unidades de hora
	CPI		R17, 4							// Si llegó a 4 revisar si decenas = 2 para reiniciar hora
	BREQ	VERIFY_24HRS_ALARMA
	CPI		R17, 10							// Si llegó a 10 poner en 0 e incrementar decenas
	BREQ	INCREMENTAR_DEC_HORA_ALARMA
	RJMP	GUARDAR_INC_HORA_ALARMA
INCREMENTAR_DEC_HORA_ALARMA:
	CLR		R17
	INC		R18								// Incrementar decenas de hora

// Verificar si llegó a 24 horas para reiniciar a 00
VERIFY_24HRS_ALARMA:
	CPI		R17, 4
	BREQ	COMPARAR_DEC_HORA_INC_ALARMA
	RJMP	GUARDAR_INC_HORA_ALARMA
COMPARAR_DEC_HORA_INC_ALARMA:
	CPI		R18, 2
	BREQ	LIMPIAR_HORA_INC_ALARMA
	RJMP	GUARDAR_INC_HORA_ALARMA
// Limpiar
LIMPIAR_HORA_INC_ALARMA:
	CLR		R17
	CLR		R18

// Guardar valores
GUARDAR_INC_HORA_ALARMA:
	STS		UN_HORA_ALARMA, R17
	STS		DEC_HORA_ALARMA, R18
	RJMP	EXIT_MODE_7

/* Decrementar hora de alarma */
DECREMENTAR_HORA_ALARMA:
	// Cargar valores de hora de alarma a registros
	LDS		R17, UN_HORA_ALARMA
	LDS		R18, DEC_HORA_ALARMA
	DEC		R17								// Decrementar unidades de hora
	CPI		R17, 255						// Llegó a 0 poner en 9 y decrementar decenas de hora
	BREQ	DECREMENTAR_DEC_HORA_ALARMA
	RJMP	GUARDAR_DEC_HORA_ALARMA
DECREMENTAR_DEC_HORA_ALARMA:
	LDI		R17, 9
	DEC		R18								// Decrementar decenas de hora
	CPI		R18, 255						// Si llegó a 0 reiniciar
	BREQ	LIMPIAR_HORA_DEC_ALARMA
	RJMP	GUARDAR_DEC_HORA_ALARMA
// Reiniciar hora (23)
LIMPIAR_HORA_DEC_ALARMA:
	LDI		R17, 3
	LDI		R18, 2

// Guardar valores
GUARDAR_DEC_HORA_ALARMA:
	STS		UN_HORA_ALARMA, R17
	STS		DEC_HORA_ALARMA, R18
	RJMP	EXIT_MODE_7
	
EXIT_MODE_7:
	RJMP	MULTIPLEXAR


/******************************************* MULTIPLEXACION **********************************************/
/* Subrutina encargada de cambiar de display encendido cada 4ms cuando timer0 enciende la bandera MULTIPLEXION */
MULTIPLEXACION:
	CLI
	// Revisar si la bandera Multiplexion = 1 para cambiar de display encendido
	LDS		R16, MULTIPLEXION
	CPI		R16, 0x01
	BRNE	NO_MULTIPLEXAR	
	// Limpiar bandera
	CLR		R16
	STS		MULTIPLEXION, R16
	SEI
	RJMP	MULTIPLEXAR_VALORES
// Si la bandera no está encendida salir
NO_MULTIPLEXAR:
	SEI
	RJMP	EXIT_MULTIPLEXACION

// Multiplexar
MULTIPLEXAR_VALORES:
// Revisar el modo actual para ver que valor se debe mostrar (hora, fecha u hora de alarma)
MULTIPLEXAR_MODE0:
	LDS		R16, MODE
	CPI		R16, 0x00
	BRNE	MULTIPLEXAR_MODE1	
	RJMP	VALORES_MODE_0					// Saltar a multiplexar valores de modo 0 
MULTIPLEXAR_MODE1:
	CPI		R16, 0x01
	BRNE	MULTIPLEXAR_MODE2
	RJMP	VALORES_MODE_1					// Saltar a multiplexar valores de modo 1
MULTIPLEXAR_MODE2:
	CPI		R16, 0x02
	BRNE	MULTIPLEXAR_MODE3
	RJMP	VALORES_MODE_2					// Saltar a multiplexar valores de modo 2
MULTIPLEXAR_MODE3:
	CPI		R16, 0x03
	BRNE	MULTIPLEXAR_MODE4
	RJMP	VALORES_MODE_3					// Saltar a multiplexar valores de modo 3
MULTIPLEXAR_MODE4:
	CPI		R16, 0x04
	BRNE	MULTIPLEXAR_MODE5
	RJMP	VALORES_MODE_4					// Saltar a multiplexar valores de modo 4
MULTIPLEXAR_MODE5:
	CPI		R16, 0x05
	BRNE	MULTIPLEXAR_MODE6
	RJMP	VALORES_MODE_5					// Saltar a multiplexar valores de modo 5
MULTIPLEXAR_MODE6:
	CPI		R16, 0x06
	BRNE	MULTIPLEXAR_MODE7
	RJMP	VALORES_MODE_6					// Saltar a multiplexar valores de modo 6
MULTIPLEXAR_MODE7:
	CPI		R16, 0x07
	BRNE	SALIDA
	RJMP	VALORES_MODE_7					// Saltar a multiplexar valores de modo 7
SALIDA:
	RJMP	EXIT_MULTIPLEXACION

// Si es modo 0 multiplexar valores de hora
VALORES_MODE_0:
	RJMP MOSTRAR_HORA

// Si es modo 1 multiplexar valores de fecha
VALORES_MODE_1:
	RJMP MOSTRAR_DIA

// Si es modo 2 multiplexar valores de hora
VALORES_MODE_2:
	RJMP MOSTRAR_HORA

// Si es modo 3 multiplexar valores de hora
VALORES_MODE_3:
	RJMP MOSTRAR_HORA

// Si es modo 4 multiplexar valores de fecha
VALORES_MODE_4:
	RJMP MOSTRAR_DIA

// Si es modo 5 multiplexar valores de fecha
VALORES_MODE_5:
	RJMP MOSTRAR_DIA

// Si es modo 6 multiplexar valores de hora de alarma
VALORES_MODE_6:
	RJMP MOSTRAR_HORA_ALARMA

// Si es modo 7 multiplexar valores de hora de alarma
VALORES_MODE_7:
	RJMP MOSTRAR_HORA_ALARMA

// Multiplexar valores de hora
MOSTRAR_HORA:
	LDS		R16, MULTIPLEXOR
	CPI		R16, 0b00001110
	BREQ	CAMBIO_C1_HORA
	CPI		R16, 0b00001101
	BREQ	CAMBIO_C2_HORA
	CPI		R16, 0b00001011
	BREQ	CAMBIO_C3_HORA
	CPI		R16, 0b00000111
	BREQ	CAMBIO_C0_HORA
CAMBIO_C0_HORA:
	LDI		R16, 0b00001110
	LDS		R17, UN_MIN
	RJMP GUARDAR_VALORES_HORA
CAMBIO_C1_HORA:
	LDI		R16, 0b00001101
	LDS		R17, DEC_MIN
	RJMP GUARDAR_VALORES_HORA
CAMBIO_C2_HORA:
	LDI		R16, 0b00001011
	LDS		R17, UN_HORA
	RJMP GUARDAR_VALORES_HORA
CAMBIO_C3_HORA:
	LDI		R16, 0b00000111
	LDS		R17, DEC_HORA
	RJMP GUARDAR_VALORES_HORA
GUARDAR_VALORES_HORA:
	STS		MULTIPLEXOR, R16
	STS		DISP_VALUE, R17
	RJMP EXIT_MULTIPLEXACION

// Multiplexar valores de fecha
MOSTRAR_DIA:
	LDS		R16, MULTIPLEXOR
	CPI		R16, 0b00001110
	BREQ	CAMBIO_C1_DIA
	CPI		R16, 0b00001101
	BREQ	CAMBIO_C2_DIA
	CPI		R16, 0b00001011
	BREQ	CAMBIO_C3_DIA
	CPI		R16, 0b00000111
	BREQ	CAMBIO_C0_DIA
CAMBIO_C0_DIA:
	LDI		R16, 0b00001110
	LDS		R17, UN_MES
	RJMP GUARDAR_VALORES_DIA
CAMBIO_C1_DIA:
	LDI		R16, 0b00001101
	LDS		R17, DEC_MES
	RJMP GUARDAR_VALORES_DIA
CAMBIO_C2_DIA:
	LDI		R16, 0b00001011
	LDS		R17, UN_DIA
	RJMP GUARDAR_VALORES_DIA
CAMBIO_C3_DIA:
	LDI		R16, 0b00000111
	LDS		R17, DEC_DIA
	RJMP GUARDAR_VALORES_DIA
GUARDAR_VALORES_DIA:
	STS		MULTIPLEXOR, R16
	STS		DISP_VALUE, R17
	RJMP EXIT_MULTIPLEXACION

// Multiplexar valores de hora de alarma
MOSTRAR_HORA_ALARMA:
	LDS		R16, MULTIPLEXOR
	CPI		R16, 0b00001110
	BREQ	CAMBIO_C1_HORA_ALARMA
	CPI		R16, 0b00001101
	BREQ	CAMBIO_C2_HORA_ALARMA
	CPI		R16, 0b00001011
	BREQ	CAMBIO_C3_HORA_ALARMA
	CPI		R16, 0b00000111
	BREQ	CAMBIO_C0_HORA_ALARMA
CAMBIO_C0_HORA_ALARMA:
	LDI		R16, 0b00001110
	LDS		R17, UN_MIN_ALARMA
	RJMP GUARDAR_VALORES_HORA_ALARMA
CAMBIO_C1_HORA_ALARMA:
	LDI		R16, 0b00001101
	LDS		R17, DEC_MIN_ALARMA
	RJMP GUARDAR_VALORES_HORA_ALARMA
CAMBIO_C2_HORA_ALARMA:
	LDI		R16, 0b00001011
	LDS		R17, UN_HORA_ALARMA
	RJMP GUARDAR_VALORES_HORA_ALARMA
CAMBIO_C3_HORA_ALARMA:
	LDI		R16, 0b00000111
	LDS		R17, DEC_HORA_ALARMA
	RJMP GUARDAR_VALORES_HORA_ALARMA
GUARDAR_VALORES_HORA_ALARMA:
	STS		MULTIPLEXOR, R16
	STS		DISP_VALUE, R17
	RJMP EXIT_MULTIPLEXACION

EXIT_MULTIPLEXACION:
	RJMP	MOSTRAR
	

/*********************************************************************************************************/
// NON-Interrupt subroutines
// INICIALIZACIÓN TIMER 1 (500ms)
INIT_TMR1:
	CLR		R16
	STS		TCCR1A, R16						// Configuración modo normal
	LDI		R16, (1 << CS12)				// Prescaler 256
	STS		TCCR1B, R16
	LDI		R16, HIGH(TMR1_VALUE)			// Cargar valor TCNT1
	STS		TCNT1H, R16							
	LDI		R16, LOW(TMR1_VALUE)				
	STS		TCNT1L, R16							
	RET

// INICIALIZACIÓN TIMER 0 (4ms)
INIT_TMR0:
	CLR		R16
	OUT		TCCR0A, R16						// Configuración modo normal
	LDI		R16, (1 << CS02)				// Prescaler 256
	OUT		TCCR0B , R16					// Cargar valor TCNT0
	LDI		R16, TMR0_VALUE					
	OUT		TCNT0, R16						
	RET


/**********************************************************************************************************/
// Interrupt routines
// Pin Change Pin B0
PINB_ISR:
	PUSH R16								// Guardar R16
    IN   R16, SREG							// Guardar Status Register
    PUSH R16
    IN   R16, PINB							// Leer Pin B
    SBRS R16, PB0							// Si B0 está en 1, salir de rutina
    RJMP AUMENTAR_MODE						// Aumentar modo
    RJMP EXIT_PINB_ISR
// Aumentar MODE
AUMENTAR_MODE:
    LDS  R16, MODE							// Cargar MODE a R16
    INC  R16								// Incremntar MODE
    CPI  R16, MAX_MODES						// Limitar MODE a MAX_MODES (8)
    BRLO GUARDAR_MODE
    CLR  R16
GUARDAR_MODE:
    STS MODE, R16							// Guardar R16 en MODE
// Salida ISR
EXIT_PINB_ISR:
    POP  R16								
    OUT  SREG, R16							// Cargar SREG
    POP  R16								// Cargar R16
	RETI

// Pin Change Pin C4-C5
PINC_ISR:
	IN		R16, SREG						// Guardar R16
	PUSH	R16								// Guardar Status Register
	IN R16, PINC							// Lectura de Pin C
    ANDI R16, 0b00110000
    LDS R17, ESTADO							// Cargar ESTADO en R17

	// Revisar botón de incremento respecto a su estado anterior
    SBRS R17, 4
    RJMP CHEQUEO
    SBRC R16, 4				
    RJMP CHEQUEO

	// Encender bandera Incrementar
    LDI	R17, 0x01		
    STS INCREMENTAR, R17		

// Revisar botón de decremento respecto a su estado anterior
CHEQUEO:
    LDS R17, ESTADO			
    SBRS R17, 5				
    RJMP GUARDAR
    SBRC R16, 5				
    RJMP GUARDAR

	// Encender bandera Decrementar
    LDI	R17, 0x01			
    STS DECREMENTAR, R17

// Guardar estado de botones
GUARDAR:
    STS ESTADO, R16
	POP R16
	OUT SREG, R16							// Devolver valores de SREG
	RETI

// ISR Timer0
TMR0_ISR:
	PUSH	R16								// Guardar valor de R16
	IN		R16, SREG						
	PUSH	R16								// Guardar valores de SREG
	PUSH	R17								// Guardar valor de R17
	// Recarga de timer
	LDI		R16, TMR0_VALUE
	OUT		TCNT0, R16
	// Encender bandera para multiplexión
	LDI		R16, 0x01
	STS		MULTIPLEXION, R16
// Salida de ISR
EXIT_TMR0_ISR:
	POP		R17								// Devolver valor de R17
	POP		R16								
	OUT		SREG, R16						// Devolver valor de SREG
	POP		R16								// Devolver valor de R16
	RETI

// ISR Timer1
TMR1_ISR:
	PUSH	R16								// Guardar valor de R16
	IN		R16, SREG						
	PUSH	R16								// Guardar valores de SREG
	PUSH	R17								// Guardar valor de R17
	// Recargar timer
	LDI		R16, HIGH(TMR1_VALUE)
	STS		TCNT1H, R16
	LDI		R16, LOW(TMR1_VALUE)
	STS		TCNT1L, R16
	// Parpadeo dos puntos
	LDI		R16, 0b10000000
	EOR		PUNTO, R16
	// Espera de 60 segundos
	LDS		R16, TIEMPO
	INC		R16								// Aumentar contador TIEMPO
	CPI		R16, 120						// Revisar si TIEMPO llegó a 120
	BRNE	EXIT_TMR1_ISR
	// Encender bandera para contar
	LDI		R16, 0x01
	STS		CONTAR, R16
	CLR		R16
// Salida de ISR
EXIT_TMR1_ISR:
	STS	TIEMPO, R16							// Guardar valor de TIEMPO
	POP	R17									// Devolver valor de R17
	POP R16
	OUT SREG, R16							// Devolver valor de SREG
	POP R16									// Devolver valor de R16
	RETI

/******************************************************************************************************/