import serial
import os
import psutil
import time

processName = "Iris.exe"
# Ensure COM3 is correct and Serial Monitor is CLOSED in Arduino IDE
ser = serial.Serial('COM3', 9600, timeout=1) 
print(f"Connected to: {ser.name}")
print("Time, Cycle Length, Cycle Number")

count = 0
start = time.time()

while True:
    # Read line and convert from bytes to string
    line = ser.readline().decode('utf-8').strip()
    
    if line:
        print(f"Arduino says: {line}") # This helps you see it's not frozen

        if line == "booted":
            print("--- Starting Iris Automation ---")
            start = time.time()
            count += 1
            
            autoit_exe = r"C:\PROGRA~2\AutoIt3\AutoIt3.exe"
            script_path = r"C:\Users\virtek\Downloads\projectIris.au3"
            
            # Run the command
            os.system(f"{autoit_exe} {script_path}")   
        if line == "off":
            end = time.time()
            duration = round(end - start, 2)
            print(f"RESULT: {time.strftime('%x %X')}, {duration}s, Cycle: {count}")
            
            # Kill Iris process
            for proc in psutil.process_iter():
                try:
                    if proc.name() == processName:
                        proc.kill()
                        print("Iris closed.")
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    pass

ser.close()