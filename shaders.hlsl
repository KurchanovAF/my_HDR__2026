// Структура данных, которая передается от вершинного шейдера к пиксельному
struct VS_OUTPUT
{
    float4 Pos : SV_POSITION; // Позиция вершины на экране
    float2 Tex : TEXCOORD0;   // Текстурные координаты кадра
};

// Вершинный шейдер (просто передает геометрию экрана дальше)
VS_OUTPUT VS(float4 Pos : POSITION, float2 Tex : TEXCOORD)
{
    VS_OUTPUT output = (VS_OUTPUT)0;
    output.Pos = Pos;
    output.Tex = Tex;
    return output;
}

// Объявляем входную текстуру и сэмплер Point-фильтрации
Texture2D shaderTexture : register(t0);
SamplerState samplerState0 : register(s0);

// Буфер констант для приема физических параметров из C++ кода
cbuffer cbData : register(b0)
{
    float width;     // Ширина картинки (2.0)
    float height;    // Высота картинки (2.0)
    float d_width;   // Шаг пикселя по горизонтали (0.5)
    float d_height;  // Шаг пикселя по вертикали (0.5)
};

// Константа весов для перевода RGB в монохромную яркость (Luma)
static const float3 WEIGHT = float3(0.299f, 0.587f, 0.114f);

// Пиксельный шейдер: 3-й проход (Статистический анализ блоков 4х4)
float4 PS(VS_OUTPUT input) : SV_Target
{
    float GrayMid = 0.0f; // Средняя яркость блока
    float GrayMin = 1.0f; // Самый темный пиксель в блоке
    float GrayMax = 0.0f; // Самый яркий пиксель в блоке
    float GraySqr = 0.0f; // Дисперсия (среднеквадратичное отклонение / контраст)

    float2 tex_coord;

    // Первый проход по блоку 4х4: считаем сумму яркостей и ищем экстремумы
    [unroll]
    for (int i_width = -1; i_width < 3; i_width++)
    {
        for (int i_height = -1; i_height < 3; i_height++)
        {
            // Рассчитываем точную координату соседнего пикселя в блоке
            tex_coord.x = input.Tex.x + float(i_width) * d_width;
            tex_coord.y = input.Tex.y + float(i_height) * d_height;

            // Читаем чистый, неискаженный пиксель через Point-выборку
            float4 k1 = shaderTexture.Sample(samplerState0, tex_coord);
            float gray = dot(k1.rgb, WEIGHT);

            // Накапливаем сумму для среднего значения
            GrayMid += gray;

            // Фиксируем минимум и максимум
            if (gray < GrayMin) GrayMin = gray;
            if (gray > GrayMax) GrayMax = gray;
        }
    }

    // Находим среднее значение яркости по 16 точкам
    GrayMid /= 16.0f;

    // Второй проход по блоку 4х4: строго рассчитываем среднеквадратичное отклонение
    [unroll]
    for (int j_width = -1; j_width < 3; j_width++)
    {
        for (int j_height = -1; j_height < 3; j_height++)
        {
            tex_coord.x = input.Tex.x + float(j_width) * d_width;
            tex_coord.y = input.Tex.y + float(j_height) * d_height;

            float4 k1 = shaderTexture.Sample(samplerState0, tex_coord);
            float gray = dot(k1.rgb, WEIGHT);

            // Суммируем квадраты отклонений от найденного среднего
            GraySqr += (gray - GrayMid) * (gray - GrayMid);
        }
    }

    // Финальный расчет дисперсии (контрастности макроблока)
    GraySqr = sqrt(GraySqr / 16.0f);

    // Упаковываем техническую аналитику блока в RGBA каналы пикселя
    // R = Среднее, G = Минимум, B = Максимум, A = Контраст
    return float4(GrayMid, GrayMin, GrayMax, GraySqr);
}

// Пиксельный шейдер: 4-й проход (Pass 2: Укрупненный анализ макроблоков 8х8)
float4 PS_Stage2(VS_OUTPUT input) : SV_Target
{
    float Summ_mid = 0.0f; // Переменная для укрупненного среднего значения
    float Summ_sqr = 0.0f; // Переменная для объединения дисперсий
    float Summ_min = 1.0f; // Глобальный минимум среди блоков
    float Summ_max = 0.0f; // Глобальный максимум среди блоков

    float2 tex_coord;

    // Цикл 2х2 для обхода четырех соседних блоков 4х4 (кластер 8х8 исходных пикселей)
    [unroll]
    for (int i_width = 0; i_width < 2; i_width++)
    {
        for (int i_height = 0; i_height < 2; i_height++)
        {
            // Сдвигаемся на шаг пикселя для выборки статистики соседнего блока
            tex_coord.x = input.Tex.x + float(i_width) * d_width;
            tex_coord.y = input.Tex.y + float(i_height) * d_height;

            // Читаем RGBA-вектор статистики отдельного блока 4х4 из предыдущего прохода
            float4 k1 = shaderTexture.Sample(samplerState0, tex_coord);

            // Накапливаем укрупненное среднее значение
            Summ_mid += k1.x; // k1.x — это среднее (GrayMid) из 3-го шейдера

            // Находим глобальные минимум и максимум среди подвыборок
            if (k1.y < Summ_min) Summ_min = k1.y; // k1.y — это минимум (GrayMin)
            if (k1.z > Summ_max) Summ_max = k1.z; // k1.z — это максимум (GrayMax)

            // Ваша магическая формула объединения дисперсий независимых подвыборок
            Summ_sqr += k1.x * k1.x + k1.w * k1.w; // k1.w — это среднеквадратичное отклонение (GraySqr)
        }
    }

    // Рассчитываем итоговое среднее для макроблока 8х8
    Summ_mid /= 4.0f;

    // Вычисляем математически точную дисперсию (контраст) для макроблока 8х8
    Summ_sqr = sqrt(abs(Summ_sqr / 4.0f - Summ_mid * Summ_mid));

    // Упаковываем укрупненную макроаналитику 8х8 в RGBA каналы пикселя
    return float4(Summ_mid, Summ_min, Summ_max, Summ_sqr);
}

// Пиксельный шейдер: 5-й проход (Pass 3: Фильтрация и адаптивное сжатие контрастности)
float4 PS_Stage3(VS_OUTPUT input) : SV_Target
{
    // 1. Считываем исходный "сырой" пиксель кадра (из оригинальной текстуры)
    float4 src_color = shaderTexture.Sample(samplerState0, input.Tex);
    float src_gray = dot(src_color.rgb, WEIGHT);

    // 2. Считываем вектор макростатистики 8х8, который мы посчитали в прошлый раз
    // (Он придет к нам на этом проходе через промежуточный буфер)
    float4 stats = shaderTexture.Sample(samplerState0, input.Tex);
    float macro_mid = stats.x; // Укрупненное среднее по макроблоку
    float macro_min = stats.y; // Минимум в макроблоке
    float macro_max = stats.z; // Максимум в макроблоке
    float macro_sqr = stats.w; // Дисперсия (локальный контраст) макроблока 8х8

    // 3. Ваша базовая математика адаптивного сжатия динамического диапазона (HDR-фильтр):
    // Находим отклонение текущего пикселя от среднего уровня его макроблока
    float delta = src_gray - macro_mid;

    // Защитный коэффициент от деления на ноль, который мы закладывали в 2011 году
    float denom = (macro_max - macro_min) + 0.001f;

    // Нормализуем локальный контраст внутри макроблока
    float local_contrast = delta / denom;

    // Адаптивно прижимаем глобальную яркость, но при этом УСИЛИВАЕМ локальные микродетали!
    // (Умножаем локальный контраст на дисперсию macro_sqr, чтобы вытащить скрытые контуры контура на УЗИ/рентгене)
    float out_gray = macro_mid + local_contrast * (macro_sqr * 2.0f);

    // Удерживаем итоговую яркость строго в системных рамках от 0.0 (черный) до 1.0 (белый)
    out_gray = saturate(out_gray);

    // Переносим рассчитанную попиксельную яркость в финальный RGBA цвет кадра
    float4 final_color = float4(out_gray, out_gray, out_gray, 1.0f);

    return final_color;
}
