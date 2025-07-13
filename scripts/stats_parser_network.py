#!/usr/bin/env python3

"""
stats_parser_network.py

Versión especializada del parser para experimentos de red TCP/IP entre 2 PCs.
Maneja los logs separados del servidor y cliente, y combina las métricas
para obtener una visión completa del rendimiento de red.
"""

import os
import re
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
import sys

# --- Constantes y Configuración ---
BASE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
RAW_RESULTS_DIR = os.path.join(BASE_DIR, "results", "raw")
FINAL_RESULTS_DIR = os.path.join(BASE_DIR, "results")
CHARTS_DIR = os.path.join(FINAL_RESULTS_DIR, "charts")
SUMMARY_CSV_PATH = os.path.join(FINAL_RESULTS_DIR, "summary_network.csv")

# Asegurarse de que el directorio de gráficos exista
os.makedirs(CHARTS_DIR, exist_ok=True)

# --- Funciones de Parsing (igual que stats_parser.py) ---

def parse_time_log(file_path):
    """Parsea el output de /usr/bin/time -v."""
    metrics = {}
    try:
        with open(file_path, 'r') as f:
            content = f.read()
            
            # Wall clock time
            match = re.search(r'Elapsed \(wall clock\) time \(h:mm:ss or m:ss\): (.*?)\n', content)
            if match:
                time_str = match.group(1)
                parts = list(map(float, time_str.split(':')))
                if len(parts) == 3: # h:mm:ss.ss
                    metrics['time_elapsed_s'] = parts[0] * 3600 + parts[1] * 60 + parts[2]
                elif len(parts) == 2: # m:ss.ss
                    metrics['time_elapsed_s'] = parts[0] * 60 + parts[1]
            
            # User/System time y CPU
            match = re.search(r'User time \(seconds\): (.*?)\n', content)
            if match: metrics['time_user_s'] = float(match.group(1))
            
            match = re.search(r'System time \(seconds\): (.*?)\n', content)
            if match: metrics['time_system_s'] = float(match.group(1))

            match = re.search(r'Percent of CPU this job got: (.*?)%\n', content)
            if match: metrics['cpu_percent'] = float(match.group(1))
            
    except (IOError, ValueError):
        pass
    return metrics

def parse_strace_log(file_path):
    """Parsea el output de strace -c."""
    syscalls = {}
    try:
        with open(file_path, 'r') as f:
            lines = f.readlines()
            header_found = False
            for line in lines:
                if 'calls' in line and 'syscall' in line:
                    header_found = True
                    continue
                if header_found and '---' not in line and line.strip():
                    parts = line.split()
                    if len(parts) >= 5:
                        syscall_name = parts[-1]
                        calls = int(parts[-2])
                        syscalls[f'syscall_{syscall_name}'] = calls
    except (IOError, IndexError):
        pass
    return syscalls

def parse_app_log(file_path):
    """Parsea el output custom de los programas en C."""
    app_metrics = {}
    try:
        with open(file_path, 'r') as f:
            for line in f:
                if ':' in line:
                    key, value = line.split(':', 1)
                    app_metrics[key.strip()] = value.strip()
    except IOError:
        pass
    return app_metrics

def get_file_size_bytes(size_str):
    """Convierte un string como '10M' a bytes."""
    size_map = {'K': 1024, 'M': 1024**2, 'G': 1024**3}
    match = re.match(r'(\d+)', size_str)
    if not match:
        return 0
    num = int(match.group(1))
    unit = size_str[-1].upper()
    return num * size_map.get(unit, 1)

# --- Proceso Principal para Red ---

def main():
    """Función principal para análisis de experimentos de red."""
    print("Iniciando análisis de resultados de red...")
    
    all_data = []

    if not os.path.exists(RAW_RESULTS_DIR):
        print(f"ERROR: El directorio de resultados crudos '{RAW_RESULTS_DIR}' no existe.")
        sys.exit(1)

    # Recorrer el árbol de directorios de resultados
    for root, _, files in os.walk(RAW_RESULTS_DIR):
        if 'time_client.log' in files or 'time_server.log' in files:
            # Extraer parámetros desde la ruta
            path_parts = root.replace(RAW_RESULTS_DIR, '').strip(os.sep).split(os.sep)
            if len(path_parts) != 5: continue
            
            mechanism, file_size_str, buffer_size_str, sync_mode, run_id = path_parts
            
            # Solo procesar TCP para experimentos de red
            if mechanism != 'tcp_socket':
                continue
                
            run_data = {
                'mechanism': mechanism,
                'file_size': file_size_str,
                'buffer_size_kb': int(buffer_size_str.replace('KB', '')),
                'sync_mode': sync_mode,
                'run': int(run_id.replace('run_', ''))
            }
            
            # Parsear logs del cliente (si existen)
            if 'time_client.log' in files:
                run_data.update(parse_time_log(os.path.join(root, 'time_client.log')))
                run_data.update(parse_strace_log(os.path.join(root, 'strace_client.log')))
                run_data.update(parse_app_log(os.path.join(root, 'app_client.log')))
                run_data['side'] = 'client'
                all_data.append(run_data.copy())
            
            # Parsear logs del servidor (si existen)
            if 'time_server.log' in files:
                server_data = run_data.copy()
                server_data.update(parse_time_log(os.path.join(root, 'time_server.log')))
                server_data.update(parse_strace_log(os.path.join(root, 'strace_server.log')))
                server_data.update(parse_app_log(os.path.join(root, 'app_server.log')))
                server_data['side'] = 'server'
                all_data.append(server_data)

    if not all_data:
        print("No se encontraron datos de logs de red para analizar.")
        return

    # Convertir a DataFrame de Pandas
    df = pd.DataFrame(all_data)

    # --- Limpieza y Cálculo de Métricas Derivadas ---
    df['file_size_bytes'] = df['file_size'].apply(get_file_size_bytes)
    
    # Usar el tiempo apropiado según el lado (cliente o servidor)
    df['TimeTaken'] = pd.to_numeric(df['TimeTaken'], errors='coerce')
    df['TimeTakenClient'] = pd.to_numeric(df['TimeTakenClient'], errors='coerce')
    df['TimeTakenServer'] = pd.to_numeric(df['TimeTakenServer'], errors='coerce')
    
    # Para el cliente, usar TimeTakenClient; para el servidor, usar TimeTakenServer
    df['time_s'] = df.apply(lambda row: 
        row['TimeTakenClient'] if row['side'] == 'client' else row['TimeTakenServer'], axis=1)
    df['time_s'] = df['time_s'].fillna(df['time_elapsed_s'])
    
    # Calcular Throughput (MB/s)
    df['throughput_mb_s'] = df['file_size_bytes'] / (1024**2) / df['time_s']
    df.replace([np.inf, -np.inf], np.nan, inplace=True)

    print(f"Se procesaron {len(df)} registros de experimentos de red.")

    # --- Análisis Estadístico ---
    # Agrupar por parámetros del experimento y lado (cliente/servidor)
    stats_df = df.groupby(['mechanism', 'file_size', 'buffer_size_kb', 'sync_mode', 'side']).agg(
        mean_throughput_mb_s=('throughput_mb_s', 'mean'),
        std_throughput_mb_s=('throughput_mb_s', 'std'),
        mean_time_s=('time_s', 'mean'),
        std_time_s=('time_s', 'std'),
        mean_cpu_percent=('cpu_percent', 'mean'),
        mean_user_time_s=('time_user_s', 'mean'),
        mean_system_time_s=('time_system_s', 'mean'),
        count=('run', 'count')
    ).reset_index()

    # Calcular intervalo de confianza del 95%
    stats_df['ci95_throughput'] = 1.96 * stats_df['std_throughput_mb_s'] / np.sqrt(stats_df['count'])
    
    # Guardar el resumen estadístico
    stats_df.to_csv(SUMMARY_CSV_PATH, index=False)
    print(f"Resumen estadístico guardado en: {SUMMARY_CSV_PATH}")

    # --- Generación de Gráficos Especializados para Red ---
    print("Generando gráficos de análisis de red...")
    sns.set_theme(style="whitegrid")

    # 1. Comparación Cliente vs Servidor
    plt.figure(figsize=(15, 8))
    g = sns.boxplot(data=df, x='file_size', y='throughput_mb_s', hue='side',
                    order=['10M', '100M', '1G'])
    g.set_title('Rendimiento TCP/IP: Cliente vs Servidor', fontsize=16)
    g.set_xlabel('Tamaño de Archivo', fontsize=12)
    g.set_ylabel('Rendimiento (MB/s)', fontsize=12)
    g.set_yscale('log')
    g.legend(title='Lado')
    plt.tight_layout()
    plt.savefig(os.path.join(CHARTS_DIR, 'tcp_client_vs_server.png'))

    # 2. Análisis de Llamadas al Sistema por Lado
    syscall_cols = [c for c in df.columns if 'syscall_' in c]
    if syscall_cols:
        syscall_df = df[df['file_size'] == '100M']  # Caso representativo
        syscall_stats = syscall_df.groupby('side')[syscall_cols].mean().reset_index()
        
        # Seleccionar llamadas relevantes
        relevant_syscalls = ['syscall_read', 'syscall_write', 'syscall_sendto', 'syscall_recvfrom']
        relevant_cols = [c for c in syscall_stats.columns if c in relevant_syscalls or c == 'side']
        syscall_stats_melted = syscall_stats[relevant_cols].melt(id_vars='side', var_name='syscall', value_name='count')
        syscall_stats_melted = syscall_stats_melted[syscall_stats_melted['count'] > 0]
        
        plt.figure(figsize=(12, 7))
        g = sns.barplot(data=syscall_stats_melted, x='side', y='count', hue='syscall')
        g.set_title('Llamadas al Sistema: Cliente vs Servidor (Archivo 100M)', fontsize=16)
        g.set_xlabel('Lado', fontsize=12)
        g.set_ylabel('Número Promedio de Llamadas', fontsize=12)
        plt.tight_layout()
        plt.savefig(os.path.join(CHARTS_DIR, 'tcp_syscalls_by_side.png'))

    # 3. Análisis de Tiempo de CPU por Lado
    cpu_df = df[df['file_size'] == '100M']
    cpu_stats = cpu_df.groupby('side')[['time_user_s', 'time_system_s']].mean().reset_index()
    cpu_stats_melted = cpu_stats.melt(id_vars='side', var_name='cpu_type', value_name='time_s')
    
    plt.figure(figsize=(10, 6))
    g = sns.barplot(data=cpu_stats_melted, x='side', y='time_s', hue='cpu_type')
    g.set_title('Tiempo de CPU: Cliente vs Servidor (Archivo 100M)', fontsize=16)
    g.set_xlabel('Lado', fontsize=12)
    g.set_ylabel('Tiempo Promedio (s)', fontsize=12)
    plt.tight_layout()
    plt.savefig(os.path.join(CHARTS_DIR, 'tcp_cpu_time_by_side.png'))

    print("Gráficos de red generados y guardados en:", CHARTS_DIR)
    print("\nAnálisis de red completado exitosamente.")

if __name__ == '__main__':
    main() 