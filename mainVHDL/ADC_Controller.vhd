LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY ADC_Controller IS
  PORT (
    CLK : IN STD_LOGIC; -- 50 MHz system clock
    NRST : IN STD_LOGIC; -- Active-low asynchronous reset
    ADC_CSN : OUT STD_LOGIC; -- ADC SPI chip-select
    ADC_SCLK : OUT STD_LOGIC; -- ADC SPI SCLK
    ADC_MOSI : OUT STD_LOGIC; -- ADC SPI MOSI
    ADC_MISO : IN STD_LOGIC; -- ADC SPI MISO
    uart_send_trigger : OUT STD_LOGIC;
    LEDS : OUT STD_LOGIC_VECTOR(7 DOWNTO 0) -- 8-bit ADC OUTPUT
  );
END ADC_Controller;

ARCHITECTURE behavioral OF ADC_Controller IS

  CONSTANT SPI_CLK_DIV : INTEGER := 156;
  CONSTANT DATA_WIDTH : INTEGER := 16; -- for ADC128S022

  TYPE state_type IS (ST_IDLE, ST_START, ST_SCK_H, ST_SCK_L, ST_WAIT);
  SIGNAL state : state_type := ST_IDLE;

  SIGNAL cs_n : STD_LOGIC := '1';
  SIGNAL sclk : STD_LOGIC := '0';
  SIGNAL mosi : STD_LOGIC := '0';

  SIGNAL bit_index : INTEGER RANGE 0 TO DATA_WIDTH - 1 := 0;
  SIGNAL adc_data : STD_LOGIC_VECTOR(11 DOWNTO 0) := (OTHERS => '0');
  SIGNAL channel : STD_LOGIC_VECTOR(2 DOWNTO 0) := "000";

  SIGNAL shift_en : STD_LOGIC := '0';
  SIGNAL shift_reg : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);

  CONSTANT WAIT_CNT_MAX : INTEGER := 31;
  SIGNAL wait_cnt : INTEGER := 0;

BEGIN

  adc_csn <= cs_n;
  adc_sclk <= sclk;
  adc_mosi <= mosi;

--  LEDS <= adc_data(11 downto 4); -- show 8-bit ADC value directly to LEDs

  PROCESS (adc_data)
    VARIABLE leds_on : INTEGER RANGE 0 TO 7;
    VARIABLE value : INTEGER RANGE 0 TO 255;
  BEGIN
    -- value := to_integer(unsigned(adc_data(11 DOWNTO 4)));
    -- value := value / 32;
    -- leds_on := value;
    LEDS <= (OTHERS => '0'); -- Default to all LEDs OFF
    LEDS(7 DOWNTO 0) <= (adc_data(11 DOWNTO 4)); -- Turn ON the corresponding LEDs
  END PROCESS;

  PROCESS (CLK, NRST)
    VARIABLE count : INTEGER RANGE 0 TO SPI_CLK_DIV - 1 := 0;
  BEGIN
    IF NRST = '0' THEN
      count := 0;
      shift_en <= '0';
    ELSIF rising_edge(CLK) THEN
      IF count = SPI_CLK_DIV - 1 THEN
        count := 0;
        shift_en <= '1';
      ELSE
        count := count + 1;
        shift_en <= '0';
      END IF;
    END IF;
  END PROCESS;

  PROCESS (CLK, NRST)
  BEGIN
    IF NRST = '0' THEN
      cs_n <= '1';
      mosi <= '0';
      sclk <= '0';
      adc_data <= (OTHERS => '0');
      channel <= (OTHERS => '0');
      bit_index <= 0;
      wait_cnt <= 0;
      state <= ST_IDLE;
      uart_send_trigger <= '0';

    ELSIF rising_edge(CLK) THEN

      CASE state IS
        WHEN ST_IDLE =>
          bit_index <= 0;
          channel <= "001"; -- Select channel ADC_IN1
          cs_n <= '1';
          sclk <= '1';
          state <= ST_START;
          uart_send_trigger <= '0';

        WHEN ST_START =>
          shift_reg <= (OTHERS => '0');
          shift_reg(13 DOWNTO 11) <= channel; -- for ADC128S022
          cs_n <= '0';
          state <= ST_SCK_L;
          uart_send_trigger <= '0';

        WHEN ST_SCK_L =>
          IF shift_en = '1' THEN
            sclk <= '0';
            mosi <= shift_reg(shift_reg'left);
            state <= ST_SCK_H;
          END IF;
          uart_send_trigger <= '0';

        WHEN ST_SCK_H =>
          IF shift_en = '1' THEN
            sclk <= '1';
            shift_reg <= shift_reg(shift_reg'left - 1 DOWNTO 0) & adc_miso;
            IF bit_index = DATA_WIDTH - 1 THEN
              cs_n <= '1';
              wait_cnt <= WAIT_CNT_MAX;
              state <= ST_WAIT;
            ELSE
              bit_index <= bit_index + 1;
              state <= ST_SCK_L;
            END IF;
          END IF;
          uart_send_trigger <= '0';

        WHEN ST_WAIT =>
          adc_data <= shift_reg(11 DOWNTO 0);
          
          IF wait_cnt = 0 THEN
            state <= ST_IDLE;
				uart_send_trigger <= '1';
          ELSE
            wait_cnt <= wait_cnt - 1;
				uart_send_trigger <= '0';
          END IF;

        WHEN OTHERS =>
          state <= ST_IDLE;
          uart_send_trigger <= '0';
      END CASE;
    END IF;
  END PROCESS;

END behavioral;