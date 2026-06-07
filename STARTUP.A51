#include <reg51.h>

// LCD Connections
sbit RS = P3^4;
sbit RW = P3^2;
sbit EN = P3^5;
#define LCD_PORT P2

// Ultrasonic Sensor 1 (Object Detection) - 13cm threshold
sbit TRIG1 = P1^4;
sbit ECHO1 = P1^5;

// Ultrasonic Sensor 2 (Garbage Depth) - Max 10cm bin
sbit TRIG2 = P1^6;
sbit ECHO2 = P1^7;

// LED Connections (Using P0)
sbit GREEN_LED = P0^0;   // Blinks 3 sec when object detected
sbit RED_LED = P0^1;     // Blinks 3 sec when object removed

// Relay for Buzzer (Using P0)
sbit RELAY = P0^2;       // Beeps when bin FULL only

// Global variables
unsigned int obj_distance;
unsigned int bin_depth;
unsigned char green_blink_active;
unsigned char red_blink_active;
unsigned int green_blink_counter;
unsigned int red_blink_counter;
unsigned int buzzer_timer;
unsigned char buzzer_state;      // 1 = ON phase, 0 = OFF phase
unsigned char prev_object_state; // 0 = No Object, 1 = Object Detected

//------------------------------------------
void delay_ms(unsigned int ms)
{
    unsigned int i, j;
    for(i = 0; i < ms; i++)
        for(j = 0; j < 1275; j++);
}

void delay_us(unsigned int us)
{
    unsigned int i;
    for(i = 0; i < us; i++);
}

//------------------------------------------
void lcd_cmd(unsigned char c)
{
    LCD_PORT = c;
    RS = 0; RW = 0;
    EN = 1; delay_ms(2);
    EN = 0; delay_ms(2);
}

void lcd_data(unsigned char d)
{
    LCD_PORT = d;
    RS = 1; RW = 0;
    EN = 1; delay_ms(2);
    EN = 0; delay_ms(2);
}

void lcd_str(char *s)
{
    while(*s) lcd_data(*s++);
}

void lcd_init(void)
{
    delay_ms(50);
    lcd_cmd(0x38); // 2 lines, 5x7 matrix
    delay_ms(5);
    lcd_cmd(0x0C); // Display ON, Cursor OFF
    delay_ms(5);
    lcd_cmd(0x01); // Clear display
    delay_ms(20);
}

//------------------------------------------
void timer0_init(void)
{
    TMOD = 0x01; // Timer 0 Mode 1 (16-bit)
}

// Read Sensor 1 (Object Detection)
unsigned int read_sensor1(void)
{
    unsigned int pulse, t, dist;
   
    TRIG1 = 0;
    delay_us(5);
    TRIG1 = 1;
    delay_us(10);
    TRIG1 = 0;
   
    t = 0;
    while(ECHO1 == 0 && t < 30000)
    {
        t++;
        delay_us(1);
    }
    if(ECHO1 == 0) return 999;
   
    TH0 = 0;
    TL0 = 0;
    TR0 = 1;
   
    t = 0;
    while(ECHO1 == 1 && t < 30000)
    {
        t++;
        delay_us(1);
    }
    TR0 = 0;
   
    pulse = (TH0 * 256) + TL0;
    dist = pulse / 58;
   
    if(dist > 400 || dist < 2) return 999;
    return dist;
}

// Read Sensor 2 (Bin Depth)
unsigned int read_sensor2(void)
{
    unsigned int pulse, t, dist;
   
    TRIG2 = 0;
    delay_us(5);
    TRIG2 = 1;
    delay_us(10);
    TRIG2 = 0;
   
    t = 0;
    while(ECHO2 == 0 && t < 30000)
    {
        t++;
        delay_us(1);
    }
    if(ECHO2 == 0) return 999;
   
    TH0 = 0;
    TL0 = 0;
    TR0 = 1;
   
    t = 0;
    while(ECHO2 == 1 && t < 30000)
    {
        t++;
        delay_us(1);
    }
    TR0 = 0;
   
    pulse = (TH0 * 256) + TL0;
    dist = pulse / 58;
   
    if(dist > 400 || dist < 2) return 999;
    return dist;
}

//------------------------------------------
void display_bin_status(unsigned int depth)
{
    lcd_cmd(0x80); // Move cursor to Line 1
   
    if(depth == 999 || depth > 12)
    {
        lcd_str("Bin: Scanning   ");
    }
    else if(depth <= 2)
    {
        lcd_str("Bin: Full Bin   ");
    }
    else if(depth <= 7)
    {
        lcd_str("Bin: Half Bin   ");
    }
    else if(depth <= 10)
    {
        lcd_str("Bin: Empty Bin  ");
    }
    else
    {
        lcd_str("Bin: Unknown    ");
    }
}

void display_object_status(unsigned int dist)
{
    lcd_cmd(0xC0); // Move cursor to Line 2
   
    if(dist != 999 && dist <= 13)
    {
        lcd_str("Obj: Detected   ");
    }
    else
    {
        lcd_str("Obj:Not Detected");
    }
}

//------------------------------------------
void main(void)
{
    // Initialize all pins to output low state
    TRIG1 = 0;
    TRIG2 = 0;
    GREEN_LED = 0;
    RED_LED = 0;
    RELAY = 0;
   
    // Initialize standard peripherals
    lcd_init();
    timer0_init();
   
    // Display targeted startup message
    lcd_str(" Smart Dustbin  ");
    delay_ms(2000);
    lcd_cmd(0x01); // Clear window
    delay_ms(10);
   
    // Initialize states
    green_blink_active = 0;
    red_blink_active = 0;
    green_blink_counter = 0;
    red_blink_counter = 0;
   
    buzzer_timer = 0;
    buzzer_state = 1;      // Prime for instant deployment (Starts at ON loop)
    prev_object_state = 0; // Baseline at startup
   
    while(1)
    {
        // Gather sensory records
        bin_depth = read_sensor2();
        obj_distance = read_sensor1();
       
        // Refresh display interfaces
        display_bin_status(bin_depth);
        display_object_status(obj_distance);
       
        // ========================================
        // COMPACT INTERLINKED DIRECTION LED SEQUENCER
        // ========================================
        if(obj_distance != 999 && obj_distance <= 13)
        {
            if(prev_object_state == 0) // Crossover event detected
            {
                green_blink_active = 1;
                green_blink_counter = 0;
               
                red_blink_active = 0;    // Clear counter/state of conflicting LED
                RED_LED = 0;
               
                prev_object_state = 1;
            }
        }
        else
        {
            if(prev_object_state == 1) // Dropped out of scope event detected
            {
                red_blink_active = 1;
                red_blink_counter = 0;
               
                green_blink_active = 0;  // Clear counter/state of conflicting LED
                GREEN_LED = 0;
               
                prev_object_state = 0;
            }
        }
       
        // Handle blinking operations without nesting core execution threads
        if(green_blink_active == 1)
        {
            green_blink_counter++;
            if(green_blink_counter <= 30) // 30 cycles * 100ms = 3.0 seconds
            {
                if((green_blink_counter % 2) == 0) GREEN_LED = 1;
                else                               GREEN_LED = 0;
            }
            else
            {
                GREEN_LED = 0;
                green_blink_active = 0;
            }
        }
       
        if(red_blink_active == 1)
        {
            red_blink_counter++;
            if(red_blink_counter <= 30) // 30 cycles * 100ms = 3.0 seconds
            {
                if((red_blink_counter % 2) == 0) RED_LED = 1;
                else                             RED_LED = 0;
            }
            else
            {
                RED_LED = 0;
                red_blink_active = 0;
            }
        }
       
        // ========================================
        // INSTANT RESPONDING BUZZER LOGIC
        // ========================================
        if(bin_depth != 999 && bin_depth <= 2)  // Full Bin State
        {
            if(buzzer_state == 1) // ON Phase
            {
                RELAY = 1;
                buzzer_timer++;
                if(buzzer_timer >= 30)
                {
                    buzzer_state = 0;
                    buzzer_timer = 0;
                    RELAY = 0;
                }
            }
            else                  // OFF Phase
            {
                RELAY = 0;
                buzzer_timer++;
                if(buzzer_timer >= 30)
                {
                    buzzer_state = 1;
                    buzzer_timer = 0;
                    RELAY = 1;
                }
            }
        }
        else  // Half Bin, Empty Bin, Scanning or Error State
        {
            RELAY = 0;
            buzzer_timer = 0;
            buzzer_state = 1; // Re-arm instantly for immediate beep when bin becomes full again
        }
       
        delay_ms(100); // 100ms Master Clock Cadence
    }
}