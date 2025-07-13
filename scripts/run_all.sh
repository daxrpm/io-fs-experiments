#!/bin/bash

# ==============================================================================
# run_all.sh: Script de Orquestación de Experimentos de E/S
#
# Este script ejecuta una batería de pruebas para comparar el rendimiento de
# diferentes mecanismos de E/S en Linux. Automatiza la ejecución de cada
# prueba bajo varias condiciones (tamaño de archivo, tamaño de buffer, modo sync)
# y recopila métricas de rendimiento usando 'time' y 'strace'.
#
# ¡ADVERTENCIA! La ejecución completa de este script puede tardar mucho tiempo
# y ejerce una carga significativa en el sistema.
# ==============================================================================

# --- Configuración del Experimento ---
set -e  # Salir inmediatamente si un comando falla

# Parámetros de prueba
REPETITIONS=10
FILE_SIZES_STR=("10M" "100M" "1G")
BUFFER_SIZES_KB=(4 64 1024) # en Kilobytes
SYNC_MODES=("nosync" "sync")

# Rutas y Comandos
BASE_DIR=$(git rev-parse --show-toplevel)/lab2-io-fs-experiments
SRC_DIR="$BASE_DIR"
BIN_DIR="$SRC_DIR/bin"
TEST_DATA_DIR="$SRC_DIR/test_data"
RESULTS_DIR="$SRC_DIR/results/raw"
SCRIPTS_DIR="$SRC_DIR/scripts"

# ¡CRÍTICO! Directorio de prueba en un FS ext4 limpio.
# Debe estar montado y con permisos de escritura para el usuario.
TEST_MOUNT="/mnt/ext4test"
if [ ! -d "$TEST_MOUNT" ] || [ ! -w "$TEST_MOUNT" ]; then
    echo "ERROR: El directorio de prueba '$TEST_MOUNT' no existe o no tiene permisos de escritura."
    echo "Por favor, créelo, móntelo con ext4 y déle permisos."
    exit 1
fi

# Configuración de red para pruebas TCP
TCP_SERVER_IP="127.0.0.1" # Cambiar si el servidor está en otra máquina
TCP_PORT=12345
UNIX_SOCKET_PATH="$TEST_MOUNT/test_socket.sock"

# --- Funciones Auxiliares ---

# Función para limpiar la caché de disco. Requiere configuración de sudo sin contraseña.
drop_caches() {
    echo "--- Limpiando cachés de disco ---"
    # sync para asegurar que todo se escriba en disco
    sync
    # El comando recomendado en el README para evitar problemas de permisos
    echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
    if [ $? -ne 0 ]; then
        echo "ERROR: No se pudo limpiar la caché. ¿Está 'sudo' configurado correctamente?"
        exit 1
    fi
    sleep 1 # Darle un segundo al sistema para que se estabilice
}

# --- Lógica Principal del Experimento ---

echo "==============================================="
echo "  INICIANDO EXPERIMENTO DE RENDIMIENTO DE E/S  "
echo "==============================================="
echo "Fecha: $(date)"
echo "Repeticiones por prueba: $REPETITIONS"
echo "Directorio de resultados: $RESULTS_DIR"
echo

# Asegurarse de que los binarios estén compilados
if [ ! -f "$BIN_DIR/file_buffered" ]; then
    echo "ERROR: Los programas no están compilados. Ejecute 'make' en el directorio raíz."
    exit 1
fi

# Bucle principal de repeticiones
for (( i=1; i<=REPETITIONS; i++ )); do
    echo "********** INICIANDO REPETICIÓN $i/$REPETITIONS **********"
    
    # Bucle de tamaños de archivo
    for size_str in "${FILE_SIZES_STR[@]}"; do
        INPUT_FILE="$TEST_DATA_DIR/file_${size_str}.dat"
        if [ ! -f "$INPUT_FILE" ]; then
            echo "AVISO: El archivo de prueba '$INPUT_FILE' no existe. Omitiendo tamaño $size_str."
            continue
        fi
        
        # Bucle de tamaños de buffer
        for bsize_kb in "${BUFFER_SIZES_KB[@]}"; do
            BSIZE_BYTES=$((bsize_kb * 1024))
            
            # Bucle de modos de sincronización
            for sync_mode in "${SYNC_MODES[@]}"; do
                SYNC_FLAG=""
                if [ "$sync_mode" == "sync" ]; then
                    SYNC_FLAG="--sync"
                fi

                # --- 1. Prueba: file_buffered ---
                LOG_DIR="$RESULTS_DIR/buffered/$size_str/${bsize_kb}KB/$sync_mode/run_$i"
                mkdir -p "$LOG_DIR"
                OUTPUT_FILE="$TEST_MOUNT/output.dat"
                
                echo "-> Test: buffered | Archivo: $size_str | Buffer: ${bsize_kb}KB | Sync: $sync_mode | Rep: $i"
                drop_caches
                ( /usr/bin/time -v strace -c -o "$LOG_DIR/strace.log" \
                    "$BIN_DIR/file_buffered" "$INPUT_FILE" "$OUTPUT_FILE" "$BSIZE_BYTES" $SYNC_FLAG > "$LOG_DIR/app.log" ) \
                    2> "$LOG_DIR/time.log"
                rm -f "$OUTPUT_FILE"

                # --- 2. Prueba: file_direct ---
                # O_DIRECT requiere que el tamaño del buffer sea múltiplo de 512
                if (( BSIZE_BYTES % 512 == 0 )); then
                    LOG_DIR="$RESULTS_DIR/direct/$size_str/${bsize_kb}KB/$sync_mode/run_$i"
                    mkdir -p "$LOG_DIR"
                    OUTPUT_FILE="$TEST_MOUNT/output.dat"
                    
                    echo "-> Test: direct   | Archivo: $size_str | Buffer: ${bsize_kb}KB | Sync: $sync_mode | Rep: $i"
                    drop_caches
                    ( /usr/bin/time -v strace -c -o "$LOG_DIR/strace.log" \
                        "$BIN_DIR/file_direct" "$INPUT_FILE" "$OUTPUT_FILE" "$BSIZE_BYTES" $SYNC_FLAG > "$LOG_DIR/app.log" ) \
                        2> "$LOG_DIR/time.log"
                    rm -f "$OUTPUT_FILE"
                fi

                # --- 3. Prueba: file_sendfile (no usa buffer, se ejecuta una vez por sync_mode) ---
                if [ $bsize_kb -eq 4 ]; then # Solo ejecutar una vez, no depende de bsize
                    LOG_DIR="$RESULTS_DIR/sendfile/$size_str/0KB/$sync_mode/run_$i"
                    mkdir -p "$LOG_DIR"
                    OUTPUT_FILE="$TEST_MOUNT/output.dat"

                    echo "-> Test: sendfile | Archivo: $size_str | Buffer: N/A | Sync: $sync_mode | Rep: $i"
                    drop_caches
                    ( /usr/bin/time -v strace -c -o "$LOG_DIR/strace.log" \
                        "$BIN_DIR/file_sendfile" "$INPUT_FILE" "$OUTPUT_FILE" $SYNC_FLAG > "$LOG_DIR/app.log" ) \
                        2> "$LOG_DIR/time.log"
                    rm -f "$OUTPUT_FILE"
                fi
            done # Fin sync_modes
            
            # --- 4. Prueba: UNIX Sockets (no usa --sync) ---
            LOG_DIR="$RESULTS_DIR/unix_socket/$size_str/${bsize_kb}KB/nosync/run_$i"
            mkdir -p "$LOG_DIR"
            OUTPUT_FILE="$TEST_MOUNT/output.dat"

            echo "-> Test: unix     | Archivo: $size_str | Buffer: ${bsize_kb}KB | Sync: N/A | Rep: $i"
            drop_caches
            # Iniciar servidor en segundo plano
            ( "$BIN_DIR/unix_socket_server" "$UNIX_SOCKET_PATH" "$OUTPUT_FILE" "$BSIZE_BYTES" > "$LOG_DIR/app_server.log" ) &
            SERVER_PID=$!
            sleep 1 # Dar tiempo al servidor para que inicie
            # Ejecutar cliente
            ( /usr/bin/time -v strace -c -o "$LOG_DIR/strace.log" \
                "$BIN_DIR/unix_socket_client" "$UNIX_SOCKET_PATH" "$INPUT_FILE" "$BSIZE_BYTES" > "$LOG_DIR/app.log" ) \
                2> "$LOG_DIR/time.log"
            # Esperar y matar al servidor
            wait $SERVER_PID || true # 'true' para no fallar si ya terminó
            rm -f "$OUTPUT_FILE"

            # --- 5. Prueba: TCP Sockets (no usa --sync) ---
            LOG_DIR="$RESULTS_DIR/tcp_socket/$size_str/${bsize_kb}KB/nosync/run_$i"
            mkdir -p "$LOG_DIR"
            OUTPUT_FILE="$TEST_MOUNT/output.dat"
            
            echo "-> Test: tcp      | Archivo: $size_str | Buffer: ${bsize_kb}KB | Sync: N/A | Rep: $i"
            drop_caches
            # Iniciar servidor
            ( "$BIN_DIR/tcp_server" "$TCP_PORT" "$OUTPUT_FILE" "$BSIZE_BYTES" > "$LOG_DIR/app_server.log" ) &
            SERVER_PID=$!
            sleep 1
            # Ejecutar cliente
            ( /usr/bin/time -v strace -c -o "$LOG_DIR/strace.log" \
                "$BIN_DIR/tcp_client" "$TCP_SERVER_IP" "$TCP_PORT" "$INPUT_FILE" "$BSIZE_BYTES" > "$LOG_DIR/app.log" ) \
                2> "$LOG_DIR/time.log"
            wait $SERVER_PID || true
            rm -f "$OUTPUT_FILE"
            
        done # Fin buffer_sizes
    done # Fin file_sizes
done # Fin repetitions

echo "==============================================="
echo "       EXPERIMENTO COMPLETADO CON ÉXITO        "
echo "==============================================="
echo "Los resultados crudos se encuentran en: $RESULTS_DIR"
echo "Para analizar los resultados, ejecute: python3 scripts/stats_parser.py" 