/*
 * 光伏发电站 IEC 60870-5-104 模拟器
 * 基于开源 lib60870 库
 *
 * 功能：
 * - 总召唤 (General Interrogation) - COT=20
 * - 变化上报 (Spontaneous Transmission) - COT=3
 * - 遥控命令处理
 */

#include <stdlib.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <signal.h>
#include <math.h>
#include <time.h>
#include <unistd.h>

#include "cs104_slave.h"
#include "hal_thread.h"
#include "hal_time.h"

static bool running = true;
static CS104_Slave slave = NULL;

// 变化检测阈值
#define FLOAT_CHANGE_THRESHOLD 1.0    // 浮点数变化阈值
#define SPONTANEOUS_INTERVAL 5        // 变化上报最小间隔(秒)

// 光伏数据结构
typedef struct {
    int ioa;
    float value;
    float last_reported_value;  // 上次上报的值
    time_t last_report_time;    // 上次上报时间
    char name[64];
} PVDataPoint;

// 3个逆变器的数据点 (IOA 1-30)
PVDataPoint inverters[30];

// 环境数据 (IOA 100-105)
PVDataPoint environment[6] = {
    {100, 800.0, 0, 0, "Irradiance"},
    {101, 25.0, 0, 0, "Ambient_Temp"},
    {102, 45.0, 0, 0, "Module_Temp"},
    {103, 3.0, 0, 0, "Wind_Speed"},
    {104, 180.0, 0, 0, "Wind_Direction"},
    {105, 60.0, 0, 0, "Humidity"}
};

// 电站汇总 (IOA 200-205)
PVDataPoint station[6] = {
    {200, 45.0, 0, 0, "Total_Active_Power"},
    {201, 5.0, 0, 0, "Total_Reactive_Power"},
    {202, 0.98, 0, 0, "Power_Factor"},
    {203, 50.0, 0, 0, "Grid_Frequency"},
    {204, 0.0, 0, 0, "Daily_Energy"},
    {205, 12500.0, 0, 0, "Total_Energy"}
};

// 逆变器状态 (IOA 1001-1003)
bool inverter_status[3] = {true, true, true};
bool inverter_status_last[3] = {true, true, true};

void sigint_handler(int signalId)
{
    running = false;
}

// 获取太阳辐照系数
float get_solar_factor() {
    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    float hour = tm_info->tm_hour + tm_info->tm_min / 60.0;

    if (hour < 6 || hour > 18) return 0.0;

    float solar_angle = (hour - 6) / 12.0 * M_PI;
    float base_factor = sin(solar_angle);
    float cloud_factor = 1.0 + ((rand() % 30) - 15) / 100.0;

    float result = base_factor * cloud_factor;
    return result > 0 ? result : 0;
}

// 初始化逆变器数据点
void init_inverters() {
    const char *names[] = {
        "DC_Voltage", "DC_Current", "DC_Power",
        "AC_Voltage_A", "AC_Voltage_B", "AC_Voltage_C",
        "AC_Current_A", "AC_Current_B", "AC_Current_C", "AC_Power"
    };

    for (int inv = 0; inv < 3; inv++) {
        for (int i = 0; i < 10; i++) {
            int idx = inv * 10 + i;
            inverters[idx].ioa = idx + 1;
            snprintf(inverters[idx].name, 64, "INV%d_%s", inv+1, names[i]);
            inverters[idx].value = 0.0;
            inverters[idx].last_reported_value = 0.0;
            inverters[idx].last_report_time = 0;
        }
    }
}

// 更新逆变器数据
void update_inverter(int inv_id, float solar_factor) {
    int base = inv_id * 10;

    if (!inverter_status[inv_id]) {
        // 逆变器停机
        for (int i = 0; i < 10; i++) {
            if (i == 1 || i == 2 || i >= 6) // 电流和功率
                inverters[base + i].value = 0.0;
        }
        return;
    }

    // DC侧
    inverters[base + 0].value = 600 + solar_factor * 150 + (rand() % 20 - 10);
    float dc_current = solar_factor * 45 + (rand() % 4 - 2);
    inverters[base + 1].value = dc_current > 0 ? dc_current : 0;
    inverters[base + 2].value = inverters[base + 0].value * inverters[base + 1].value / 1000;

    // AC侧电压
    for (int i = 3; i < 6; i++) {
        inverters[base + i].value = 400 + (rand() % 10 - 5);
    }

    // AC侧电流和功率
    float ac_power = inverters[base + 2].value * 0.97;
    float ac_current = (solar_factor > 0) ? ac_power * 1000 / (400 * 1.732) : 0;
    for (int i = 6; i < 9; i++) {
        float val = ac_current + (rand() % 2 - 1);
        inverters[base + i].value = val > 0 ? val : 0;
    }
    inverters[base + 9].value = ac_power;
}

// 更新环境数据
void update_environment(float solar_factor) {
    float val = solar_factor * 1000 + (rand() % 100 - 50);
    if (val < 0) val = 0;
    if (val > 1200) val = 1200;
    environment[0].value = val;

    float base_temp = 20 + 10 * sin((time(NULL) % 86400) / 86400.0 * 2 * M_PI);
    environment[1].value = base_temp + (rand() % 4 - 2);
    environment[2].value = environment[1].value + solar_factor * 25 + (rand() % 6 - 3);

    val = 3 + (rand() % 10 - 4);
    environment[3].value = val > 0 ? val : 0;
    environment[4].value = fmod(environment[4].value + (rand() % 20 - 10) + 360, 360);
    val = 70 - solar_factor * 20 + (rand() % 10 - 5);
    if (val < 20) val = 20;
    if (val > 95) val = 95;
    environment[5].value = val;
}

// 更新电站汇总
void update_station() {
    float total_power = 0;
    for (int i = 0; i < 3; i++) {
        total_power += inverters[i * 10 + 9].value;
    }

    station[0].value = total_power;
    station[1].value = total_power * 0.05 + (rand() % 4 - 2);
    station[2].value = (total_power > 0) ? 0.98 + (rand() % 3 - 1) / 100.0 : 1.0;
    station[3].value = 50.0 + (rand() % 20 - 10) / 100.0;
    station[4].value += total_power / 3600.0; // 累计日发电量
    station[5].value += total_power / 3600000.0; // 累计总发电量
}

// 检查浮点数是否需要上报变化
bool should_report_change(PVDataPoint *point, float threshold) {
    time_t now = time(NULL);
    float change = fabs(point->value - point->last_reported_value);

    // 检查变化是否超过阈值，且距离上次上报超过最小间隔
    if (change >= threshold && (now - point->last_report_time) >= SPONTANEOUS_INTERVAL) {
        return true;
    }
    return false;
}

// 发送变化上报 (Spontaneous) - 浮点数
void send_spontaneous_float(PVDataPoint *point) {
    if (slave == NULL) return;

    CS101_AppLayerParameters alParams = CS104_Slave_getAppLayerParameters(slave);

    CS101_ASDU asdu = CS101_ASDU_create(alParams, false, CS101_COT_SPONTANEOUS,
                                         0, 1, false, false);

    InformationObject io = (InformationObject)
        MeasuredValueShort_create(NULL, point->ioa, point->value, IEC60870_QUALITY_GOOD);

    CS101_ASDU_addInformationObject(asdu, io);
    InformationObject_destroy(io);

    CS104_Slave_enqueueASDU(slave, asdu);
    CS101_ASDU_destroy(asdu);

    // 更新上报记录
    point->last_reported_value = point->value;
    point->last_report_time = time(NULL);

    printf("[变化上报] IOA=%d (%s) 值=%.2f\n", point->ioa, point->name, point->value);
}

// 发送变化上报 (Spontaneous) - 单点状态
void send_spontaneous_single_point(int ioa, bool value) {
    if (slave == NULL) return;

    CS101_AppLayerParameters alParams = CS104_Slave_getAppLayerParameters(slave);

    CS101_ASDU asdu = CS101_ASDU_create(alParams, false, CS101_COT_SPONTANEOUS,
                                         0, 1, false, false);

    InformationObject io = (InformationObject)
        SinglePointInformation_create(NULL, ioa, value, IEC60870_QUALITY_GOOD);

    CS101_ASDU_addInformationObject(asdu, io);
    InformationObject_destroy(io);

    CS104_Slave_enqueueASDU(slave, asdu);
    CS101_ASDU_destroy(asdu);

    printf("[变化上报] IOA=%d 状态=%s\n", ioa, value ? "ON" : "OFF");
}

// 检查并发送所有变化
void check_and_send_changes() {
    // 检查逆变器数据变化
    for (int i = 0; i < 30; i++) {
        if (should_report_change(&inverters[i], FLOAT_CHANGE_THRESHOLD)) {
            send_spontaneous_float(&inverters[i]);
        }
    }

    // 检查环境数据变化
    for (int i = 0; i < 6; i++) {
        float threshold = (i == 0) ? 50.0 : FLOAT_CHANGE_THRESHOLD;  // 辐照度阈值更大
        if (should_report_change(&environment[i], threshold)) {
            send_spontaneous_float(&environment[i]);
        }
    }

    // 检查电站汇总变化
    for (int i = 0; i < 6; i++) {
        float threshold = (i == 4 || i == 5) ? 10.0 : FLOAT_CHANGE_THRESHOLD;  // 电量阈值更大
        if (should_report_change(&station[i], threshold)) {
            send_spontaneous_float(&station[i]);
        }
    }

    // 检查逆变器状态变化
    for (int i = 0; i < 3; i++) {
        if (inverter_status[i] != inverter_status_last[i]) {
            send_spontaneous_single_point(1001 + i, inverter_status[i]);
            inverter_status_last[i] = inverter_status[i];
        }
    }
}

// 总召唤处理 (General Interrogation)
static bool interrogationHandler(void* parameter, IMasterConnection connection, CS101_ASDU asdu, uint8_t qoi)
{
    printf("\n========== 收到总召唤命令 QOI=%i ==========\n", qoi);

    if (qoi == 20) { // 站召唤
        CS101_AppLayerParameters alParams = IMasterConnection_getApplicationLayerParameters(connection);

        // 发送确认 (ACT_CON)
        IMasterConnection_sendACT_CON(connection, asdu, false);
        printf("[总召唤] 发送确认 ACT_CON\n");

        // 发送逆变器数据 (使用短浮点数 M_ME_NC_1, TypeID=13)
        printf("[总召唤] 发送逆变器数据 IOA 1-30 (M_ME_NC_1)\n");
        CS101_ASDU newAsdu = CS101_ASDU_create(alParams, false, CS101_COT_INTERROGATED_BY_STATION,
                                                0, 1, false, false);

        for (int i = 0; i < 30; i++) {
            InformationObject io = (InformationObject)
                MeasuredValueShort_create(NULL, inverters[i].ioa,
                                          inverters[i].value, IEC60870_QUALITY_GOOD);
            CS101_ASDU_addInformationObject(newAsdu, io);
            InformationObject_destroy(io);

            if (CS101_ASDU_getNumberOfElements(newAsdu) >= 20) {
                IMasterConnection_sendASDU(connection, newAsdu);
                CS101_ASDU_destroy(newAsdu);
                newAsdu = CS101_ASDU_create(alParams, false, CS101_COT_INTERROGATED_BY_STATION,
                                            0, 1, false, false);
            }
        }

        // 发送环境数据
        printf("[总召唤] 发送环境数据 IOA 100-105 (M_ME_NC_1)\n");
        for (int i = 0; i < 6; i++) {
            InformationObject io = (InformationObject)
                MeasuredValueShort_create(NULL, environment[i].ioa,
                                          environment[i].value, IEC60870_QUALITY_GOOD);
            CS101_ASDU_addInformationObject(newAsdu, io);
            InformationObject_destroy(io);
        }

        // 发送电站汇总
        printf("[总召唤] 发送电站汇总 IOA 200-205 (M_ME_NC_1)\n");
        for (int i = 0; i < 6; i++) {
            InformationObject io = (InformationObject)
                MeasuredValueShort_create(NULL, station[i].ioa,
                                          station[i].value, IEC60870_QUALITY_GOOD);
            CS101_ASDU_addInformationObject(newAsdu, io);
            InformationObject_destroy(io);
        }

        if (CS101_ASDU_getNumberOfElements(newAsdu) > 0) {
            IMasterConnection_sendASDU(connection, newAsdu);
        }
        CS101_ASDU_destroy(newAsdu);

        // 发送逆变器状态 (单点信息 M_SP_NA_1, TypeID=1)
        printf("[总召唤] 发送逆变器状态 IOA 1001-1003 (M_SP_NA_1)\n");
        newAsdu = CS101_ASDU_create(alParams, false, CS101_COT_INTERROGATED_BY_STATION,
                                    0, 1, false, false);
        for (int i = 0; i < 3; i++) {
            InformationObject io = (InformationObject)
                SinglePointInformation_create(NULL, 1001 + i, inverter_status[i], IEC60870_QUALITY_GOOD);
            CS101_ASDU_addInformationObject(newAsdu, io);
            InformationObject_destroy(io);
        }
        IMasterConnection_sendASDU(connection, newAsdu);
        CS101_ASDU_destroy(newAsdu);

        // 发送总召唤结束 (ACT_TERM)
        IMasterConnection_sendACT_TERM(connection, asdu);
        printf("[总召唤] 发送结束 ACT_TERM\n");
        printf("========== 总召唤完成 ==========\n\n");
    }

    return true;
}

// 命令处理 (遥控)
static bool asduHandler(void* parameter, IMasterConnection connection, CS101_ASDU asdu)
{
    if (CS101_ASDU_getTypeID(asdu) == C_SC_NA_1) {
        printf("\n========== 收到单点命令 (C_SC_NA_1) ==========\n");

        InformationObject io = CS101_ASDU_getElement(asdu, 0);
        int ioa = InformationObject_getObjectAddress(io);

        if (ioa >= 2001 && ioa <= 2003) {
            SingleCommand sc = (SingleCommand) io;
            int inv_id = ioa - 2001;
            bool new_state = SingleCommand_getState(sc);

            printf("[遥控] IOA=%d 逆变器%d %s\n", ioa, inv_id + 1, new_state ? "启动" : "停止");

            inverter_status[inv_id] = new_state;

            // 发送命令确认
            IMasterConnection_sendACT_CON(connection, asdu, false);
            printf("[遥控] 发送确认 ACT_CON\n");
            printf("========== 命令处理完成 ==========\n\n");
        }

        InformationObject_destroy(io);
        return true;
    }

    return false;
}

// 连接事件处理
static bool connectionRequestHandler(void* parameter, const char* ipAddress)
{
    printf("\n[连接] 客户端连接请求: %s\n", ipAddress);
    return true;
}

static void connectionEventHandler(void* parameter, IMasterConnection con, CS104_PeerConnectionEvent event)
{
    if (event == CS104_CON_EVENT_CONNECTION_OPENED) {
        printf("[连接] 客户端已连接\n");
    }
    else if (event == CS104_CON_EVENT_CONNECTION_CLOSED) {
        printf("[连接] 客户端已断开\n");
    }
    else if (event == CS104_CON_EVENT_ACTIVATED) {
        printf("[连接] 连接已激活 (STARTDT)\n");
    }
    else if (event == CS104_CON_EVENT_DEACTIVATED) {
        printf("[连接] 连接已停用 (STOPDT)\n");
    }
}

int main(int argc, char** argv)
{
    srand(time(NULL));

    printf("======================================================================\n");
    printf("       光伏发电站 IEC 60870-5-104 协议模拟器 (开源版)\n");
    printf("       基于 lib60870 开源库\n");
    printf("======================================================================\n\n");

    // 初始化数据
    init_inverters();

    printf("数据点配置:\n");
    printf("  IOA 1-30:      逆变器1-3 模拟量 (M_ME_NC_1, TypeID=13)\n");
    printf("  IOA 100-105:   环境监测数据 (M_ME_NC_1, TypeID=13)\n");
    printf("  IOA 200-205:   电站汇总数据 (M_ME_NC_1, TypeID=13)\n");
    printf("  IOA 1001-1003: 逆变器状态 (M_SP_NA_1, TypeID=1)\n");
    printf("  IOA 2001-2003: 逆变器控制 (C_SC_NA_1, TypeID=45)\n\n");

    printf("支持功能:\n");
    printf("  - 总召唤 (General Interrogation, COT=20)\n");
    printf("  - 变化上报 (Spontaneous, COT=3)\n");
    printf("  - 遥控命令 (Single Command)\n\n");

    // 创建服务器
    slave = CS104_Slave_create(10, 10);
    CS104_Slave_setLocalAddress(slave, "0.0.0.0");
    CS104_Slave_setLocalPort(slave, 2404);

    // 设置回调
    CS104_Slave_setInterrogationHandler(slave, interrogationHandler, NULL);
    CS104_Slave_setASDUHandler(slave, asduHandler, NULL);
    CS104_Slave_setConnectionRequestHandler(slave, connectionRequestHandler, NULL);
    CS104_Slave_setConnectionEventHandler(slave, connectionEventHandler, NULL);

    // 启动服务器
    CS104_Slave_start(slave);

    if (CS104_Slave_isRunning(slave) == false) {
        printf("启动服务器失败!\n");
        goto exit_program;
    }

    printf("服务器启动成功\n");
    printf("监听地址: 0.0.0.0:2404\n");
    printf("站地址 (Common Address): 1\n\n");
    printf("======================================================================\n");
    printf("服务器运行中... 按 Ctrl+C 停止\n");
    printf("======================================================================\n\n");

    signal(SIGINT, sigint_handler);

    int counter = 0;
    while (running) {
        Thread_sleep(1000);

        // 更新数据
        float solar_factor = get_solar_factor();

        for (int i = 0; i < 3; i++) {
            update_inverter(i, solar_factor);
        }
        update_environment(solar_factor);
        update_station();

        // 检查并发送变化上报
        check_and_send_changes();

        // 每10秒打印一次状态
        if (++counter >= 10) {
            counter = 0;
            time_t now = time(NULL);
            struct tm *tm_info = localtime(&now);
            printf("\n[%02d:%02d:%02d] 太阳系数: %.2f | 总功率: %.1fkW | 日发电量: %.1fkWh\n",
                   tm_info->tm_hour, tm_info->tm_min, tm_info->tm_sec,
                   solar_factor, station[0].value, station[4].value);

            for (int i = 0; i < 3; i++) {
                printf("  逆变器%d: %s | 功率: %.1fkW\n",
                       i+1, inverter_status[i] ? "运行" : "停机",
                       inverters[i*10 + 9].value);
            }
        }
    }

    printf("\n正在停止服务器...\n");
    CS104_Slave_stop(slave);

exit_program:
    CS104_Slave_destroy(slave);
    printf("程序退出\n");

    return 0;
}
