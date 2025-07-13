#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <time.h>
#include <errno.h>

/**
 * file_buffered.c
 *
 * Realiza una copia de archivo utilizando E/S con búfer en espacio de usuario.
 * Este programa implementa el mecanismo de "single buffer" descrito en
 * Stallings, Cap. 11.4. Los datos se leen desde el archivo de entrada a un
 * búfer en el espacio de usuario y luego se escriben desde ese búfer al
 * archivo de salida.
 *
 * Mide el tiempo total de la operación, y cuenta el número de llamadas
 * al sistema 'read' y 'write'.
 *
 * Argumentos:
 *  - <fichero_entrada>: Ruta al archivo de origen.
 *  - <fichero_salida>: Ruta al archivo de destino.
 *  - <tam_buffer>: Tamaño del búfer de lectura/escritura en bytes.
 *  - [--sync]: Opcional. Si se especifica, se llama a fsync() para forzar
 *              la escritura a disco.
 */

void print_usage(const char *prog_name) {
    fprintf(stderr, "Uso: %s <fichero_entrada> <fichero_salida> <tam_buffer> [--sync]\n", prog_name);
}

int main(int argc, char *argv[]) {
    if (argc < 4 || argc > 5) {
        print_usage(argv[0]);
        exit(EXIT_FAILURE);
    }

    const char *input_path = argv[1];
    const char *output_path = argv[2];
    long buffer_size = atol(argv[3]);
    int use_fsync = (argc == 5 && strcmp(argv[4], "--sync") == 0);

    if (buffer_size <= 0) {
        fprintf(stderr, "Error: El tamaño del buffer debe ser un entero positivo.\n");
        exit(EXIT_FAILURE);
    }

    // --- Apertura de archivos ---
    int fd_in = open(input_path, O_RDONLY);
    if (fd_in == -1) {
        perror("Error al abrir el archivo de entrada");
        exit(EXIT_FAILURE);
    }

    int fd_out = open(output_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd_out == -1) {
        perror("Error al abrir el archivo de salida");
        close(fd_in);
        exit(EXIT_FAILURE);
    }

    // --- Asignación del búfer ---
    char *buffer = malloc(buffer_size);
    if (buffer == NULL) {
        perror("Error al asignar memoria para el buffer");
        close(fd_in);
        close(fd_out);
        exit(EXIT_FAILURE);
    }

    // --- Medición de tiempo y copia ---
    struct timespec start, end;
    long read_calls = 0;
    long write_calls = 0;
    ssize_t bytes_read;

    clock_gettime(CLOCK_MONOTONIC, &start);

    while ((bytes_read = read(fd_in, buffer, buffer_size)) > 0) {
        read_calls++;
        ssize_t bytes_written = write(fd_out, buffer, bytes_read);
        write_calls++;
        if (bytes_written != bytes_read) {
            perror("Error de escritura incompleta");
            // Se podría añadir una lógica más robusta para reintentar la escritura
            free(buffer);
            close(fd_in);
            close(fd_out);
            exit(EXIT_FAILURE);
        }
    }

    if (bytes_read == -1) {
        perror("Error de lectura");
        free(buffer);
        close(fd_in);
        close(fd_out);
        exit(EXIT_FAILURE);
    }
    
    // Forzar la escritura a disco si se especificó --sync
    if (use_fsync) {
        if (fsync(fd_out) == -1) {
            perror("Error en fsync");
            // No es fatal, pero el experimento debe registrar el error.
        }
    }

    clock_gettime(CLOCK_MONOTONIC, &end);
    
    // --- Cálculo de tiempo y resultados ---
    double time_taken = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;

    // --- Limpieza ---
    free(buffer);
    close(fd_in);
    close(fd_out);

    // --- Imprimir resultados para el parser ---
    // Este formato es clave para el script de análisis.
    printf("Mechanism: Buffered I/O\n");
    printf("BufferSize: %ld\n", buffer_size);
    printf("SyncMode: %s\n", use_fsync ? "sync" : "nosync");
    printf("TimeTaken: %.6f\n", time_taken);
    printf("ReadCalls: %ld\n", read_calls);
    printf("WriteCalls: %ld\n", write_calls);

    return 0;
} 