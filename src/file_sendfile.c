#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <time.h>
#include <errno.h>
#include <sys/sendfile.h>
#include <sys/stat.h>

/**
 * file_sendfile.c
 *
 * Realiza una copia de archivo utilizando la llamada al sistema sendfile().
 * Este es un mecanismo de "zero-copy", que evita la transferencia de datos
 * entre el espacio del kernel y el espacio de usuario. El kernel copia los
 * datos directamente desde el cache de página del archivo de entrada al
 * cache de página del archivo de salida.
 *
 * Referencia teórica: Illinois CS241 Coursebook, Sección sobre optimizaciones
 * de E/S. sendfile() minimiza el cambio de contexto y la copia de datos,
 * siendo extremadamente eficiente para transferir datos entre dos
 * descriptores de archivo.
 *
 * Argumentos:
 *  - <fichero_entrada>: Ruta al archivo de origen.
 *  - <fichero_salida>: Ruta al archivo de destino.
 *  - [--sync]: Opcional. Si se especifica, se llama a fsync() para forzar
 *              la escritura a disco.
 */

void print_usage(const char *prog_name) {
    fprintf(stderr, "Uso: %s <fichero_entrada> <fichero_salida> [--sync]\n", prog_name);
}

int main(int argc, char *argv[]) {
    if (argc < 3 || argc > 4) {
        print_usage(argv[0]);
        exit(EXIT_FAILURE);
    }

    const char *input_path = argv[1];
    const char *output_path = argv[2];
    int use_fsync = (argc == 4 && strcmp(argv[3], "--sync") == 0);

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
    
    // --- Obtener tamaño del archivo de entrada ---
    struct stat file_stat;
    if (fstat(fd_in, &file_stat) == -1) {
        perror("Error en fstat");
        close(fd_in);
        close(fd_out);
        exit(EXIT_FAILURE);
    }
    off_t file_size = file_stat.st_size;

    // --- Medición de tiempo y copia ---
    struct timespec start, end;
    
    clock_gettime(CLOCK_MONOTONIC, &start);

    ssize_t sent_bytes = sendfile(fd_out, fd_in, NULL, file_size);
    if (sent_bytes != file_size) {
        perror("Error en sendfile o escritura incompleta");
        fprintf(stderr, "Bytes enviados: %ld de %ld\n", sent_bytes, file_size);
        close(fd_in);
        close(fd_out);
        exit(EXIT_FAILURE);
    }

    if (use_fsync) {
        if (fsync(fd_out) == -1) {
            perror("Error en fsync");
        }
    }

    clock_gettime(CLOCK_MONOTONIC, &end);
    
    // --- Cálculo de tiempo y resultados ---
    double time_taken = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;

    // --- Limpieza ---
    close(fd_in);
    close(fd_out);

    // --- Imprimir resultados para el parser ---
    printf("Mechanism: sendfile\n");
    // BufferSize es N/A para sendfile, pero lo incluimos por consistencia.
    printf("BufferSize: 0\n"); 
    printf("SyncMode: %s\n", use_fsync ? "sync" : "nosync");
    printf("TimeTaken: %.6f\n", time_taken);
    // sendfile es una sola llamada, strace lo confirmará.
    printf("SendfileCalls: 1\n");

    return 0;
} 