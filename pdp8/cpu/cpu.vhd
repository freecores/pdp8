--------------------------------------------------------------------------------
--!
--! PDP-8 Processor
--!
--! \brief
--!      CPU Processor
--!
--! \details
--!      I hope you like state machines because this is implemented as one big
--!      state machine.
--!
--! \file
--!      cpu.vhd
--!
--! \author
--!      Rob Doyle - doyle (at) cox (dot) net
--!
--------------------------------------------------------------------------------
--
--  Copyright (C) 2009, 2010, 2011, 2012 Rob Doyle
--
-- This source file may be used and distributed without restriction provided
-- that this copyright statement is not removed from the file and that any
-- derivative work contains the original copyright notice and the associated
-- disclaimer.
--
-- This source file is free software; you can redistribute it and/or modify it
-- under the terms of the GNU Lesser General Public License as published by the
-- Free Software Foundation; version 2.1 of the License.
--
-- This source is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
-- FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
-- details.
--
-- You should have received a copy of the GNU Lesser General Public License
-- along with this source; if not, download it from
-- http://www.gnu.org/licenses/lgpl.txt
--
--------------------------------------------------------------------------------
--
-- Comments are formatted for doxygen
--

library ieee;                                   --! IEEE Library
use ieee.std_logic_1164.all;                    --! IEEE 1164
use ieee.numeric_std.all;                       --! IEEE Numeric Standard
use work.cpu_types.all;
-- synthesis translate_off
use std.textio.all;                             --! std textio
use ieee.std_logic_textio.all;                  --! IEEE std_logic_textio
-- synthesis translate_on

--
--! CPU Entity
--

entity eCPU is port (
    sys     : in  sys_t;                        --! Clock/Reset
    swCPU   : in  swCPU_t;                      --! CPU Configuration
    swOPT   : in  swOPT_t;                      --! Options Configuration
    swDATA  : in  swDATA_t;                     --! Data Switch Inputs
    swCNTL  : in  swCNTL_t;                     --! Control Switch Inputs
    dev     : in  dev_t;                        --! Device Output
    cpu     : out cpu_t                         --! CPU Output
);
end eCPU;

--
--! CPU RTL
--

architecture rtl of eCPU is

    --
    -- Registers
    --

    signal LAC      : ldata_t;                  --! Link and Accumulator
    alias  L        : std_logic is LAC (0);     --! Link Bit
    alias  AC       : data_t is LAC(1 to 12);   --! Accumulator
    signal IR       : data_t;                   --! Instruction Register
    signal PC       : addr_t;                   --! Program Counter
    signal MA       : addr_t;                   --! Memory Address Register
    signal MB       : data_t;                   --! Memory Buffer (output)
    signal MD       : data_t;                   --! Memory Data Register (input)
    signal MQ       : data_t;                   --! MQ Register
    signal MQA      : data_t;                   --! MQA Register
    signal SC       : sc_t;                     --! SC Register
    signal SP1      : addr_t;                   --! Stack Pointer
    signal SP2      : addr_t;                   --! Stack Pointer
    signal SR       : data_t;                   --! Switch Register

    --
    -- Register Operation
    --

    signal acOP     : acOP_t;                   --! AC operation
    signal pcOP     : pcOP_t;                   --! PC operation
    signal irOP     : irOP_t;                   --! IR operation
    signal maOP     : maOP_t;                   --! MA operation
    signal mbOP     : mbOP_t;                   --! MB operation
    signal mqOP     : mqOP_t;                   --! MQ operation
    signal mqaOP    : mqaOP_t;                  --! MQA operation
    signal scOP     : scOP_t;                   --! SC operation
    signal sp1OP    : spOP_t;                   --! SP1 operation
    signal sp2OP    : spOP_t;                   --! SP2 operation
    signal srOP     : srOP_t;                   --! SR operation

    --
    -- Memory Extension Control Registers
    --

    signal IB       : field_t;                  --! Instruction Buffer
    signal INF      : field_t;                  --! Instruction Field
    signal DF       : field_t;                  --! Data Field
    signal SF       : sf_t;                     --! Save Field

    --
    -- Memory Extension Control Register Operations
    --

    signal ibOP     : ibOP_t;                   --! IB operation
    signal ifOP     : ifOP_t;                   --! IF operation
    signal dfOP     : dfOP_t;                   --! DF operation
    signal sfOP     : sfOP_t;                   --! SF operation
    signal IRQ      : std_logic;                --! IRQ Flag

    --
    -- KM8x Time Share Registers
    --

    signal UB       : std_logic;                --! User Buffer Flag
    signal UF       : std_logic;                --! User Flag

    --
    -- KM8x Time Share Register Operations
    --

    signal ubOP     : ubOP_t;                   --! User Buffer operation
    signal ufOP     : ufOP_t;                   --! USER Flag operation

    --
    -- BTSTRP:
    --

    signal BTSTRP   : std_logic;                --! BTSTRP Register
    signal btstrpOP : btstrpOP_t;               --! BTSTRP operation

    --
    -- CTRLFF:
    -- The Control Panel Register (CTRLFF), is set when the CPREQ is granted.
    -- CTRLFF prevents further CPREQs from being granted, bypasses the
    -- interrupt enable system and redefines several of the internal control
    -- instructions.  As long as the CTRLFF is set, LXPAR is used for all
    -- instruction, direct data and indirect pointer references.  Also, while
    -- CTRLFF is set, the INTGNT line is held inactive but the Interrupt Grant
    -- Flip Flop is not cleared.  IOTs executed while CTRLFF is set do not clear
    -- the Interrupt grant flip flop.
    --

    signal CTRLFF   : std_logic;                --! CTRLFF
    signal ctrlffOP : ctrlffOP_t;               --! CTRLFF operation

    --
    -- EAE:
    -- EAE Long Operations
    --

    signal EAE      : eae_t;                    --! EAE Register
    signal eaeOP    : eaeOP_t;                  --! EAE operation

    --
    -- EMODE:
    -- The EMODE bit is set at reset and is set by the SWAB and cleared by the
    -- SWBA instructions.  This enables EAE Mode A and EAE Mode B instructions.
    --

    signal EMODE    : std_logic;                --! EAE Mode
    signal emodeOP  : emodeOP_t;                --! EAE Mode operation

    --
    -- FZ:
    -- The Force Zero Flag (FZ) is used to implement Extended memory operations
    -- for Panel Mode instructions.  When set, forces control panel instruction
    -- field access to field zero.  Indirect data accesses are not affected.
    --

    signal FZ       : std_logic;                --! Force Zero
    signal fzOP     : fzOP_t;                   --! FZ operation

    --
    -- HLTTRP:
    -- The HLTTRP flip-flop allows the cpu to single step through code.
    -- The HLTTRP flip-flop is set by a HLT instruction.
    --

    signal HLTTRP   : std_logic;                --! HLTTRP Register
    signal hlttrpOP : hlttrpOP_t;               --! HLTTRP operation

    --
    -- GTF:
    --

    signal GTF      : std_logic;                --! Greater than Flag
    signal gtfOP    : gtfOP_t;                  --! GTF operation

    --
    --! ID:
    --! The ION Delay (ID) register delays the effect of the ION
    --! instruction until the instruction after the ION
    --! instruction has executed.   This will allow a return
    --! from interrupt to be executed before the next interrupt
    --! request is serviced.
    --

    signal ID       : std_logic;                --! ION Delay Flip-flop
    signal idOP     : idOP_t;                   --! ION Delay Operation

    --
    -- IE:
    -- The Interrupt Enable Register (IE) enables and disables interrupts.
    --

    signal IE       : std_logic;                --! Interrupt Enable
    signal ieOP     : ieOP_t;                   --! IE operation

    --
    -- II:
    -- The Interrupt Inhibit (II) Register is set whenever there is an
    -- instruction executed that could change the Instruction Field.  These
    -- include CIF, CDI, RMF, RTF, CAF, CUF, SUF.  The II Register is
    -- cleared when the next JMP, JMS, RTN1, or RTN2 instruction is executed.
    -- This prevents an interrupt from occuring between the CIF (or like)
    -- instruction and the return (or like) instruction.
    --

    signal II       : std_logic;                -- Interrupt Inhibit Register
    signal iiOP     : iiOP_t;                   -- Interrupt Inhibit Operation

    --
    -- PDF:
    -- The Panel Data Flag (PDF) is used to contol whether indirectly addressed
    -- data references by Control Panel AND, TAD, ISZ or DCA instructions
    -- reference panel memory or main memory.  If PDF is set, this flag causes
    -- indirect references from control panel memory to address control panel
    -- memory by asserting LXPAR.  If PDF is cleared, this flag causes indirect
    -- references from control panel memory to address main memory by asserting
    -- LXMAR.  The PDF is cleared unconditionally whenever the panel mode is
    -- entered for any reason.  It is also cleared by the Clear Panel Data
    -- (CPD) instruction.  The PDF is set by the Set Panel Data (SPD)
    -- instruction. The state of the Panel Data flag is ignored when not
    -- operating in panel mode.
    --

    signal PDF      : std_logic;                --! Panel Data Flag
    signal pdfOP    : pdfOP_t;                  --! PDF operation

    --
    -- PEX:
    -- The Panel Exit Delay (PEX) Register is set by the PEX instruction.
    -- When a JMP, JMS, RET1, or RET2 instruction is executed with the PEX
    -- Register set, the CPU will exit panel mode.  The PEX Register is
    -- cleared by the JMP, JMS, RET1, or RET2 instruction.
    --

    signal PEX      : std_logic;                -- PEX Register
    signal pexOP    : pexOP_t;                  -- PEX Operation

    --
    -- PNLTRP:
    -- A Panel Trap is one of the many ways to enter panel mode.  The Panel Trap
    -- Register (PNLTRP) is set by any of the PR0, PR1, PR2, PR3 instructions.
    -- The PNLTRP flag can be examined and cleared by the PRS instruction.
    --

    signal PNLTRP   : std_logic;                --! PNLTRP Flag
    signal pnltrpOP : pnltrpOP_t;               --! PNLTRP operation

    --
    -- PRWON:
    -- The Power-On Trap Register (PWRTRP) is set when STRTUP is negated during
    -- RESET, The Power-On Register (PWRTRP) is reset by a PRS or PEX
    -- instruction.
    --

    signal PWRTRP   : std_logic;                --! PWRTRP Register
    signal pwrtrpOP : pwrtrpOP_t;               --! PWRTRP operation

    --
    -- USRTRP:
    -- User Mode Trap.
    --

    signal USRTRP   : std_logic;                --! USR Interrupt
    signal usrtrpOP : usrtrpOP_t;               --! USR Interrupt operation

    --
    -- XMA
    --

    signal XMA      : field_t;                  --! XMA Register
    signal xmaOP    : xmaOP_t;                  --! XMA operation

    --
    -- Bus Control Signals
    --

    signal busb     : busOP_t;                  --! Bus Operation output
    signal busOP    : busOP_t;                  --! Bus Operation input
    signal ioclrb   : std_logic;                --! IOCLR register output
    signal ioclrOP  : std_logic;                --! IOCLR register input
    signal wrb      : std_logic;                --! WR signal register input
    signal wrOP     : std_logic;                --! WR signal register output
    signal rdb      : std_logic;                --! RD signal register output
    signal rdOP     : std_logic;                --! RD signal register input
    signal ifetchb  : std_logic;                --! IFETCH signal register output
    signal ifetchOP : std_logic;                --! IFETCH signal register input
    signal datafb   : std_logic;                --! DATAF signal register output
    signal datafOP  : std_logic;                --! DATAF signal register input
    signal lxdarb   : std_logic;                --! LXDAR signal register output
    signal lxdarOP  : std_logic;                --! LXDAR signal register input
    signal lxmarb   : std_logic;                --! LXMAR signal register output
    signal lxmarOP  : std_logic;                --! LXMAR signal register input
    signal lxparb   : std_logic;                --! LXPAR signal register output
    signal lxparOP  : std_logic;                --! LXPAR signal register input
    signal memselb  : std_logic;                --! MEMSEL signal register output
    signal memselOP : std_logic;                --! MEMSEL signal register input
    signal intgntb  : std_logic;                --! INTGNT signal register output
    signal dmagnt   : std_logic;                --! DMAGNT signal register input
    signal intgntOP : std_logic;                --! INTGNT signal register input
    signal waitfb   : std_logic;                --! WAITF signal register output
    signal waitfOP  : std_logic;                --! WAITF signal register input

    signal oops     : std_logic;

    --
    -- State Information
    --

    type state_t is (
        stateReset,
        stateInit,
        stateCheckReq,
        stateFetchAddr,
        stateFetchData,
        stateLoadIR,
        stateDecodeInstruction,

        --
        -- MRI States
        --

        stateMRIreadAddr,
        stateMRIreadDataIND,
        stateMRIreadIncAddr,
        stateMRIreadIndData,
        stateMRIexecute,

        --
        -- IOT states
        --

        stateIOTdecode,
        stateIOT,

        --
        -- Stack Operation States
        --

        statePOPaddr,
        statePOPdata,
        stateRTN1,
        stateRTN2,
        stateRTNaddr,
        stateRTNdata,

        --
        -- OPR Groups
        --

        stateOprGroup1Seq3,
        stateOprGroup1Seq4,
        stateOprGroup2Seq2,
        stateOprGroup3Seq3,

        --
        -- Front Panel States
        --

        stateHalt,
        stateContinue,
        stateLoadADDR,
        stateLoadEXTD,
        stateClear,
        stateDepositWriteData,
        stateDeposit,
        stateExamine,
        stateExamineReadAddr,
        stateExamineReadData,
        stateHaltDone,

        --
        -- EAE States
        --

        stateEAEfetchAddr,
        stateEAEfetchData,
        stateEAEindWrite,
        stateEAEindReadAddr,
        stateEAEindReadData,
        stateEAEshift,
        stateEAEwait,
        stateEAEnmi,
        stateEAEshiftDVI,
        stateEAEsubDVI,
        stateEAEmuy,
        stateEAEreadDADaddr0,
        stateEAEreadDADaddr1,
        stateEAEreadDADdata0,
        stateEAEreadDADdata1,
        stateEAEdst,

        --
        -- HALT states
        --

        stateDone,
        stateLALA
    );


    signal   state      : state_t;
    signal   nextState  : state_t;
    constant maAutoIncr : std_logic_vector(3 to 11) := o"001";

    --
    -- Output files for state dumpState
    --

    -- synthesis translate_off
    file     FIL        : text is out "STD_OUTPUT";
    file     STDOUT     : text is out "STD_OUTPUT";
  --file     FIL        : text is out "trace.txt";
    -- synthesis translate_on

    --
    -- vectorize
    --

    function vectorize(s: std_logic) return std_logic_vector is
        variable v: std_logic_vector(0 to 0);
    begin
        v(0) := s;
        return v;
    end;

    --
    -- dumpState()
    --

    procedure dumpState(PC : in addr_t) is
        -- synthesis translate_off
        variable LIN : line;
        -- synthesis translate_on
    begin
        -- synthesis translate_off
        write (LIN, string'("ST:"));
        write (LIN, string'(" PC="));
        owrite(LIN, PC);
        write (LIN, string'(", IR="));
        owrite(LIN, IR);
        write (LIN, string'(", LAC="));
        owrite(LIN, "00" & LAC);
        write (LIN, string'(", MQ="));
        owrite(LIN, MQ);
        write (LIN, string'(", SR="));
        owrite(LIN, SR);
        write (LIN, string'(", IF="));
        owrite(LIN, INF);
        write (LIN, string'(", DF="));
        owrite(LIN, DF);
        write (LIN, string'(", IB="));
        owrite(LIN, IB);
        write (LIN, string'(", UB="));
        owrite(LIN, "00" & vectorize(UB));
        write (LIN, string'(", UF="));
        owrite(LIN, "00" &  vectorize(UF));
        write (LIN, string'(", USF="));
        owrite(LIN, "00" &  SF(0 to 0));
        write (LIN, string'(", ISF="));
        owrite(LIN, SF(1 to 3));
        write (LIN, string'(", DSF="));
        owrite(LIN, SF(4 to 6));
        write (LIN, string'(", SC="));
        owrite(LIN, '0' & SC);
        write (LIN, string'(", GTF="));
        owrite(LIN, "00" & vectorize(GTF));
        write (LIN, string'(", EMODE="));
        owrite(LIN, "00" & vectorize(EMODE));
        write (LIN, string'(", IEFF="));
        owrite(LIN, "00" & vectorize(IE));
        write (LIN, string'(", IDFF="));
        owrite(LIN, "00" & vectorize(ID));
        write (LIN, string'(", IIFF="));
        owrite(LIN, "00" & vectorize(II));
        write (LIN, string'(", IRQ="));
        owrite(LIN, "00" & vectorize(IRQ));
        write (LIN, string'(", SP1="));
        owrite(LIN, SP2);
        write (LIN, string'(", SP2="));
        owrite(LIN, SP1);
        write (LIN, string'("; MA=00000"));
        --owrite(LIN, XMA & MA);
        writeline(FIL, LIN);
        -- synthesis translate_on
    end dumpState;

    --
    -- dispHALT
    --

    procedure dispHALT(signal PC : in addr_t) is
        -- synthesis translate_off
       variable LIN : line;
        -- synthesis translate_on
    begin
        -- synthesis translate_off
        write (LIN, string'("CPU Halted at PC = "));
        owrite(LIN, PC);
        writeline(STDOUT, LIN);
        -- synthesis translate_on
    end dispHALT;

    --
    -- dispCONT
    --

    procedure dispCONT(signal PC : in addr_t) is
        -- synthesis translate_off
        variable LIN : line;
        -- synthesis translate_on
    begin
        -- synthesis translate_off
        write (LIN, string'("CPU Continued at PC = "));
        owrite(LIN, PC);
        writeline(STDOUT, LIN);
        -- synthesis translate_on
    end dispCONT;

begin

    IRQ <= '1' when ((dev.intr = '1') or
                     (USRTRP = '1' and swOPT.TSD = '0') or
                     (usrtrpOP = usrtrpopSET and swOPT.TSD = '0')) else '0';

    --
    --  ALU
    --

    iALU : entity work.eALU (rtl) port map (
        sys     => sys,
        acOP    => acOP,
        BTSTRP  => BTSTRP,
        GTF     => GTF,
        HLTTRP  => HLTTRP,
        IE      => IE,
        IRQ     => IRQ,
        PNLTRP  => PNLTRP,
        PWRTRP  => PWRTRP,
        DF      => DF,
        EAE     => EAE,
        INF     => INF,
        IR      => IR,
        MA      => MA,
        MD      => MD,
        MQ      => MQ,
        PC      => PC,
        SC      => SC,
        SF      => SF,
        SP1     => SP1,
        SP2     => SP2,
        SR      => SR,
        UF      => UF,
        LAC     => LAC
    );

    --
    -- CTRLFF
    --

    iCTRLFF : entity work.eCTRLFF (rtl) port map (
        sys      => sys,
        ctrlffOP => ctrlffOP,
        CTRLFF   => CTRLFF
    );

    --
    -- EAE Register
    --

    iEAE : entity work.eEAE (rtl) port map (
        sys     => sys,
        eaeOP   => eaeOP,
        MD      => MD,
        MQ      => MQ,
        AC      => AC,
        EAE     => EAE
    );

    --
    -- EAE Mode A
    --

    iEMODE : entity work.eEMODE (rtl) port map (
        sys     => sys,
        emodeOP => emodeOP,
        EMODE   => EMODE
    );

    --
    -- FZ Flip Flop
    --

    iFZ : entity work.eFZ (rtl) port map (
        sys  => sys,
        fzOP => fzOP,
        FZ   => FZ
    );

    --
    -- GTF
    --

    iGTF : entity work.eGTF (rtl) port map (
        sys   => sys,
        gtfOP => gtfOP,
        AC    => AC,
        GTF   => GTF
    );

    --
    -- HLTTRP
    --

    iHLTTRP : entity work.eHLTTRP (rtl) port map (
        sys      => sys,
        hlttrpOP => hlttrpOP,
        HLTTRP   => HLTTRP
    );

    --
    -- Program Counter (PC)
    --

    iPC : entity work.ePC (rtl) port map (
        sys  => sys,
        pcOP => pcOP,
        IR   => IR,
        MA   => MA,
        MB   => MB,
        MD   => MD,
        SR   => SR,
        PC   => PC
    );

    --
    -- Multiplier Quotient Register (MQ)
    --

    iMQ : entity work.eMQ (rtl) port map (
        sys  => sys,
        mqOP => mqOP,
        AC   => AC,
        MD   => MD,
        EAE  => EAE,
        MQ   => MQ
    );

    --
    -- Auxillary Multiplier Quotient Register (MQA)
    --

    iMQA : entity work.eMQA (rtl) port map (
        sys   => sys,
        mqaOP => mqaOP,
        MQ    => MQ,
        MQA   => MQA
    );

    --
    -- Interrupt Enable Register
    --

    iIE : entity work.eIE (rtl) port map (
        sys  => sys,
        ieOP => ieOP,
        IE   => IE
    );

    --
    -- Interrupt Inhibit Register
    --

    iII : entity work.eII (rtl) port map (
        sys  => sys,
        iiOP => iiOP,
        II   => II
    );

    --
    -- USRTRP Register
    --

    iUSRTRP : entity work.eUSRTRP (rtl) port map (
        sys      => sys,
        usrtrpOP => usrtrpOP,
        USRTRP   => USRTRP
    );

    --
    -- Instruction Register (IR)
    --

    iIR: entity work.eIR (rtl) port map (
        sys   => sys,
        irOP  => irOP,
        MD    => MD,
        IR    => IR
    );

    --
    -- Memory Address Register (MA)
    --

    iMA : entity work.eMA (rtl) port map (
        sys  => sys,
        maOP => maOP,
        IR   => IR,
        MB   => MB,
        MD   => MD,
        PC   => PC,
        SP1  => SP1,
        SP2  => SP2,
        SR   => SR,
        MA   => MA
    );

    --
    -- Memory Buffer Register (MB)
    --

    iMB : entity work.eMB (rtl) port map (
        sys  => sys,
        mbOP => mbOP,
        AC   => AC,
        MA   => MA,
        MD   => MD,
        MQ   => MQ,
        PC   => PC,
        SR   => SR,
        MB   => MB
    );

    --
    -- Instruction Buffer Address Extension Register (IB)
    --

    iIB : entity work.eIB (rtl) port map (
        sys  => sys,
        ibOP => ibOP,
        SF   => SF,
        AC   => AC,
        IR   => IR,
        IB   => IB
    );

    --
    -- Instruction Field Address Extension Register (IF/INF)
    --

    iIF : entity work.eIF (rtl) port map (
        sys  => sys,
        ifOP => ifOP,
        IB   => IB,
        SR   => SR,
        INF  => INF
    );

    --
    -- ION Delay Register
    --

    iID : entity work.eID (rtl) port map (
        sys  => sys,
        idOP => idOP,
        ID   => ID
    );

    --
    -- Data Field Address Extension Register (DF)
    --

    iDF : entity work.eDF (rtl) port map (
        sys  => sys,
        dfOP => dfOP,
        AC   => AC,
        IR   => IR,
        SF   => SF,
        SR   => SR,
        DF   => DF
    );

    --
    --! BTSTRP Register
    --

    iBTSTRP : entity work.eBTSTRP (rtl) port map (
        sys      => sys,
        btstrpOP => btstrpOP,
        BTSTRP   => BTSTRP
    );

    --
    -- PDF Register
    --

    iPDF : entity work.ePDF (rtl) port map (
        sys   => sys,
        pdfOP => pdfOP,
        PDF   => PDF
    );

    --
    -- PEX Register
    --

    iPEX : entity work.ePEX (rtl) port map (
        sys   => sys,
        pexOP => pexOP,
        PEX   => PEX
    );

    --
    -- PNLTRP Register
    --

    iPNLTRP : entity work.ePNLTRP (rtl) port map (
        sys      => sys,
        pnltrpOP => pnltrpOP,
        PNLTRP   => PNLTRP
    );

    --
    -- PWRTRP Register
    -- When set during reset, the unit will enter panel mode before executing
    -- the first instruction.
    --

    iPWRTRP : entity work.ePWRTRP (rtl) port map (
        sys      => sys,
        pwrtrpOP => pwrtrpOP,
        PWRTRP   => PWRTRP
    );

    --
    -- SC
    -- Step Counter
    --

    iSC : entity work.eeSC (rtl) port map (
        sys  => sys,
        scOP => scOP,
        AC   => AC,
        MD   => MD,
        SC   => SC
    );

    --
    -- SF
    -- Save Field Address Extension Register (SF)
    --

    iSF : entity work.eSF (rtl) port map (
        sys  => sys,
        sfOP => sfOP,
        DF   => DF,
        IB   => IB,
        UB   => UB,
        SF   => SF
    );

    --
    -- SP1
    -- Stack Pointer #1
    --

    iSP1 : entity work.eSP (rtl) port map (
        sys  => sys,
        spOP => sp1OP,
        AC   => AC,
        SP   => SP1
    );

    --
    -- SP2
    -- Stack Pointer #2
    --

    iSP2: entity work.eSP (rtl) port map (
        sys  => sys,
        spOP => sp2OP,
        AC   => AC,
        SP   => SP2
    );

    --
    -- SR
    -- Switch Register
    --

    iSR : entity work.eSR (rtl) port map (
        sys   => sys,
        swCPU => swCPU,
        srOP  => srOP,
        AC    => AC,
        SRD   => swDATA,
        SR    => SR
    );

    --
    -- UB
    -- User Buffer Flag
    --

    iUB : entity work.eUB (rtl) port map (
        sys  => sys,
        ubOP => ubOP,
        AC5  => AC(5),
        SF0  => SF(0),
        UB   => UB
    );

    --
    -- UF
    -- User Flag
    --

    iUF : entity work.eUF (rtl) port map (
        sys  => sys,
        ufOP => ufOP,
        UB   => UB,
        UF   => UF
    );

    --
    -- XMA
    -- XMA is disabled by disabling the KM8E option
    --

    iXMA : entity work.eXMA (rtl) port map (
        sys   => sys,
        xmaOP => xmaOP,
        sWCPU => swCPU,
        DF    => DF,
        INF   => INF,
        IB    => IB,
        XMA   => XMA
    );

    --
    --! CPU Next State Decoder
    --

    NEXT_STATE : process(swOPT, dev, IRQ, state, USRTRP, AC, L, MQA, BTSTRP,
                         CTRLFF, EMODE, GTF, HLTTRP, ID, IE, II, LAC, MA, MD, MQ,
                         PC, PEX, PNLTRP, PWRTRP, IR, SC, UF, swCPU, swCNTL)

        variable EAEIR : std_logic_vector(0 to 3);

    begin

        --
        -- Control signal defaults
        --

        busOP      <= busopNOP;
        ioclrOP    <= '0';
        wrOP       <= '0';
        rdOP       <= '0';
        ifetchOP   <= '0';
        datafOP    <= '0';
        lxdarOP    <= '0';
        memselOP   <= '0';
        intgntOP   <= '0';

        --
        -- Operation defaults
        --

        acOP       <= acopNOP;
        busOP      <= busopNOP;
        btstrpOP   <= btstrpopNOP;
        ctrlffOP   <= ctrlffopNOP;
        dfOP       <= dfopNOP;
        eaeOP      <= eaeopNOP;
        emodeOP    <= emodeopNOP;
        fzOP       <= fzopNOP;
        gtfOP      <= gtfopNOP;
        hlttrpOP   <= hlttrpopNOP;
        idOP       <= idopNOP;
        ieOP       <= ieopNOP;
        iiOP       <= iiopNOP;
        ibOP       <= ibopNOP;
        ifOP       <= ifopNOP;
        irOP       <= iropNOP;
        maOP       <= maopNOP;
        mbOP       <= mbopNOP;
        mqOP       <= mqopNOP;
        mqaOP      <= mqaopNOP;
        pcOP       <= pcopNOP;
        pdfOP      <= pdfopNOP;
        pexOP      <= pexopNOP;
        pnltrpOP   <= pnltrpopNOP;
        pwrtrpOP   <= pwrtrpopNOP;
        scOP       <= scopNOP;
        sfOP       <= sfopNOP;
        sp1OP      <= spopNOP;
        sp2OP      <= spopNOP;
        srOP       <= sropNOP;
        ubOP       <= ubopNOP;
        ufOP       <= ufopNOP;
        usrtrpOP   <= usrtrpopNOP;
        xmaOP      <= xmaopNOP;

        --
        -- Default Next State
        --

        nextState <= stateLALA;

        --
        -- BTSTRP set when CPREQ is asserted
        --

        if dev.cpreq = '1' and swCPU = swHD6120 then
            btstrpOP <= btstrpOPSET;
        end if;

        --
        -- The State Machine
        --

        case state is

            --
            -- Reset State
            --

            when stateRESET =>
                ioclrOP   <= '1';
                busOP     <= busopRESET;
                nextState <= stateInit;

            --
            --
            -- Startup States
            --

            when stateInit =>
                if swCPU = swHD6120 then

                    --
                    -- HD6120 Mode with STARTUP asserted.
                    -- Boot to front panel mode (PC=7777)
                    --

                    if swOPT.STARTUP = '1' then
                        pwrtrpOP  <= pwrtrpopSET;
                        nextState <= stateCheckReq;

                    --
                    -- HD6120 Mode with STARTUP negated.
                    -- Begin executing at PC=0000
                    --

                    else
                        pwrtrpOP  <= pwrtrpopCLR;
                        nextState <= stateCheckReq;

                    end if;
                else

                    --
                    -- PDP8 Mode with STARTUP asserted.
                    -- Set PC to contents of switch register and start
                    -- execution.
                    --

                    if swOPT.STARTUP = '1' then
                        pcOP      <= pcopSR;
                        nextState <= stateFetchAddr;

                    --
                    -- PDP8 Mode with STARTUP negated.
                    -- Start in HALT state.  User must interact with front
                    -- panel.
                    --

                    else
                        nextState <= stateHalt;

                    end if;
                end if;

            --
            -- This state occurs at the very top of the processing loop.
            -- The priority hierarchy is:
            -- 1.  RESET -   Clears Accummulator and Link registers and clears the
            --               RUN output signal.
            -- 2.  CPREQ -   If not RESET and CPREQ is asserted, the processor
            --               enters Panel Mode.
            -- 3.  RUN/HLT - If neither RESET or CPREQ is asserted and HLT is
            --               asserted (HLTFLAG = '1'), the processor should enter
            --               the HALT state and the end of the current cycle.
            -- 4.  DEV.INTR -  If no higher priority signal is asserted and IRQ is
            --               asserted an interrup may be processed.
            --

            when stateCheckReq =>

                --
                -- HD6120:
                -- Panel mode is entered because of the occurrence of any of
                -- four events.  Each of these events sets a status flag, as
                -- well as causing the entry into panel mode. It should be
                -- noted that more than one event might happen simultaneously.
                --
                -- These events are:
                --  1. PWRTRP  - Power-up Trap
                --  2. PNLTRP  - Panel Trap
                --  3. HLTTRP  - HLT insruction
                --  4. BTSTRP  - CPREQ asserted.
                --  5. Not already in panel mode
                --
                -- When a panel request is granted, the PC is stored in
                -- location 0000 of the control panel memory and the CPU
                -- resumes operation at location 7777 (octal) of the panel
                -- memory. During the PC write, 0 appears on EMA0, EMA1 and
                -- EMA2. The states of the IB, IF/INF, OF, ISF and DSF
                -- registers are not disturbed by entry into the control
                -- panel mode but execution is forced to commence in field
                -- zero.
                --
                -- See also description of ID, IE, and II.
                --

                if (((swCPU = swHD6120) and (ID = '0') and (II = '0') and (CTRLFF = '0') and (PWRTRP = '1')) or
                    ((swCPU = swHD6120) and (ID = '0') and (II = '0') and (CTRLFF = '0') and (PNLTRP = '1')) or
                    ((swCPU = swHD6120) and (ID = '0') and (II = '0') and (CTRLFF = '0') and (BTSTRP = '1')) or
                    ((swCPU = swHD6120) and (ID = '0') and (II = '0') and (CTRLFF = '0') and (HLTTRP = '1'))) then

                    wrOP      <= '1';
                    ctrlffOP  <= ctrlffopSET;
                    fzOP      <= fzopSET;
                    pdfOP     <= pdfopCLR;
                    maOP      <= maop0000;
                    mbOP      <= mbopPC;
                    pcOP      <= pcop7777;
                    xmaOP     <= xmaopCLR;
                    memselOP  <= '1';
                    busOP     <= busopWRZF;
                    assert false report "---------------------> Panel Trap <---------------------" severity note;
                    nextState <= stateFetchAddr;

                --
                -- HALT Mode is entered if the HLTTRP is set or the RUN/HALT
                -- Switch is in the HALT position.
                --

                elsif (((swCPU /= swHD6120) and (HLTTRP = '1')) or
                       ((swCPU /= swHD6120) and (swCNTL.halt = '1') and (swCNTL.lock = '0')) or
                       ((swCPU /= swHD6120) and (swCNTL.step = '1') and (swCNTL.lock = '0'))) then
                    hlttrpOP  <= hlttrpopCLR;
                    dispHALT(PC);
                    nextState <= stateHalt;

                --
                -- Interrupt Request
                -- When an External Interrupt is asserted, the following occurs:
                --   1.  The PC is stored in location 0000 of field 0.
                --   2.  The Interrupt Enable Register (IE) is disabled
                --       which precludes automatically nested interupts.
                --   3.  The INTGNT signal is is asserted.
                --   4.  UF, IF/INF, DF is loaded into SF.
                --   5.  IF/INF is cleared.
                --   6.  IB is cleared.
                --   7.  DF is cleared.
                --   8.  UF is cleared.
                --   9.  UB is cleared.
                --  10.  The PC is set to "0001" of main memory field 0 so
                --       that the next instruction is fetched from there.
                --
                -- See also description of ID, IE, and II.
                --

                elsif (IRQ = '1') and (ID = '0') and (IE = '1') and (II = '0') then
                    wrOP      <= '1';
                    intgntOP  <= '1';
                    maOP      <= maop0000;
                    mbOP      <= mbopPC;
                    ieOP      <= ieopCLR;
                    sfOP      <= sfopUBIBDF;
                    dfOP      <= dfopCLR;
                    ifOP      <= ifopCLR;
                    ibOP      <= ibopCLR;
                    ufOP      <= ufopCLR;
                    ubOP      <= ubopCLR;
                    pcOP      <= pcop0001;
                    xmaOP     <= xmaopCLR;
                    memselOP  <= '1';
                    busOP     <= busopWRZF;
                    assert false report "---------------------> Interrupt <---------------------" severity note;
                    nextState <= stateFetchAddr;

                --
                -- No interrupts, halt, single step, or anthing else.
                -- Just start to fetch the next instruction.
                --

                else
                    nextState <= stateFetchAddr;

                end if;

            --
            -- HALT State
            -- An HD6120 will never get to this state since halts are trapped
            -- by the front panel.
            --

            when stateHalt =>

                --
                -- Continue Switch Pressed
                --

                if ((swCNTL.cont = '1' and swCNTL.lock = '0') or
                    (swCNTL.step = '1' and swCNTL.lock = '0')) then
                    dispCONT(PC);
                    nextState <= stateContinue;

                --
                -- Load Address Switch Pressed
                -- This sets MA and PC to the contents of the switch register.
                --  MA <- SR
                --  PC <- SR
                --

                elsif swCNTL.loadADDR = '1' and swCNTL.lock = '0' then
                    pcOP      <= pcopSR;
                    maOP      <= maopSR;
                    nextState <= stateLoadADDR;

                --
                -- Load Extended Address Switch Pressed
                -- This sets IF and DF to the contents of the switch register.
                --  IF <- SR[6:8]
                --  DF <- SR[9:11]
                --

                elsif swCNTL.loadEXTD = '1' and swCNTL.lock = '0' then
                    ifOP      <= ifopSR6to8;
                    dfOP      <= dfopSR9to11;
                    nextState <= stateLoadEXTD;

                --
                -- Clear Switch Pressed
                --

                elsif swCNTL.clear = '1' and swCNTL.lock = '0' then
                    acOP      <= acopCLACLL;
                    mqOP      <= mqopCLR;
                    ifOP      <= ifopCLR;
                    ibOP      <= ibopCLR;
                    dfOP      <= dfopCLR;
                    ubOP      <= ubopCLR;
                    ufOP      <= ufopCLR;
                    sp1OP     <= spopCLR;
                    sp2OP     <= spopCLR;
                    ioclrOP   <= '1';
                    lxdarOP   <= '1';
                    datafOP   <= '1';
                    gtfOP     <= gtfopCLR;
                    emodeOP   <= emodeopCLR;
                    ieOP      <= ieopCLR;
                    idOP      <= idopSET;
                    usrtrpOP  <= usrtrpopCLR;
                    busOP     <= busopIOCLR;
                    nextState <= stateClear;

                --
                -- Examine Switch Pressed
                -- This loads the contents of the memory location addressed by
                -- the MA register into the MD register and increments the MA
                -- and PC registers.
                --  MD <- MEM[IF'MA]
                --

                elsif swCNTL.exam = '1' and swCNTL.lock = '0' then
                    maOP      <= maopPC;
                    xmaOP     <= xmaopIF;
                    memselOP  <= '1';
                    busOP     <= busopRDIFaddr;
                    nextState <= stateExamineReadAddr;

                --
                -- Deposit Switch Pressed
                -- This writes the contents of the Switch Register into the
                -- memory location addressed by the MA register.
                --  MEM[IF'MA] <- SR
                --

                elsif swCNTL.dep = '1' and swCNTL.lock = '0' then
                    wrOP      <= '1';
                    maOP      <= maopPC;
                    mbOP      <= mbopSR;
                    xmaOP     <= xmaopIF;
                    memselOP  <= '1';
                    busOP     <= busopWRIF;
                    nextState <= stateDepositWriteData;

                else
                    nextState <= stateHalt;

                end if;

            --
            -- Wait for Continue button to negate
            --

            when stateContinue =>
                if swCNTL.cont = '1' then
                    nextState <= stateContinue;
                else
                    nextState <= stateFetchAddr;
                end if;

            --
            -- Wait for LoadADDR button to negate
            --

            when stateLoadADDR =>
                if swCNTL.loadADDR = '1' then
                    nextState <= stateLoadADDR;
                else
                    nextState <= stateHaltDone;
                end if;

            --
            -- Wait for LoadEXTD button to negate
            --

            when stateLoadEXTD =>
                if swCNTL.loadEXTD = '1' then
                    nextState <= stateLoadEXTD;
                else
                    nextState <= stateHaltDone;
                end if;

            --
            -- Wait for Clear button to negate
            --

            when stateClear =>
                if swCNTL.clear = '1' then
                    nextState <= stateClear;
                else
                    nextState <= stateHaltDone;
                end if;

            --
            -- Examine Read Addr
            -- This is the address phase of the read cycle.
            --

            when stateExamineReadAddr =>
                rdOP      <= '1';
                xmaOP     <= xmaopIF;
                memselOP  <= '1';
                busOP     <= busopRDIFdata;
                nextState <= stateExamineReadData;

            --
            -- Examine Read Data
            -- This is the data phase of the read cycle.
            -- At the end of this cycle, MD will have the data that was read.
            -- This state increments the PC and MA register after the examine.
            --  MD <- MEM[IF'MA]
            --  MA <- MA + 1
            --  PC <- PC + 1
            --

            when stateExamineReadData =>
                maOP      <= maopINC;
                pcOP      <= pcopINC;
                nextState <= stateExamine;

            --
            -- Wait for Examine button to negate
            --

            when stateExamine =>
                if swCNTL.exam = '1' then
                    nextState <= stateExamine;
                else
                    nextState <= stateHaltDone;
                end if;

            --
            -- This cycle writes data to memory.  Once written
            -- this state increments PC and MA.
            --  MA <- MA + 1
            --  PC <- PC + 1
            --

            when stateDepositWriteData =>
                maOP      <= maopINC;
                pcOP      <= pcopINC;
                nextState <= stateDeposit;

            --
            -- Wait for Deposit button to negate
            --

            when stateDeposit =>
                if swCNTL.dep = '1' then
                    nextState <= stateDeposit;
                else
                    nextState <= stateHaltDone;
                end if;

            --
            -- Update Front Panel display
            --

            when stateHaltDone =>
                nextState <= stateHalt;

            --
            -- Begin Instruction Fetch.  Perform Read Address Cycle.
            --  MA <- PC
            --  MD <- MEM[IF'MA]
            --

            when stateFetchAddr =>
                maOP      <= maopPC;
                xmaOP     <= xmaopIF;
                ifetchOP  <= '1';
                memselOP  <= '1';
                busOP     <= busopFETCHaddr;
                nextState <= stateFetchData;

            --
            -- Continue Instruction Fetch.  Perform Read Data Cycle.
            -- The Interrupt Enable Delay Register (ID) is cleared.
            -- If the ID was set at the beginning of this instruction,
            -- an interrupt, if present, was deferred.  We clear it now.
            -- Therefore this instruction will complete and then that
            -- interrupt, if present, will be recognized.
            --  MD <- MEM[IF'MA]
            --

            when stateFetchData =>
                rdOP      <= '1';
                pcOP      <= pcopINC;
                idOP      <= idopCLR;
                xmaOP     <= xmaopIF;
                ifetchOP  <= '1';
                memselOP  <= '1';
                busOP     <= busopFETCHdata;
                nextState <= stateLoadIR;

            --
            -- Load IR with the instruction that was fetched.
            -- Note: This state is a wasted state.  We could have decoded the MD
            -- and loaded the IR simultaneously.
            --  IR <- MD
            --

            when stateLoadIR =>
                irOP      <= iropMD;
                nextState <= stateDecodeInstruction;

            --
            -- Decode Instruction in IR
            --

            when stateDecodeInstruction =>

                --
                -- Default Next State
                --

                nextState <= stateLALA;

                --
                -- Parse OPCODE
                --

                case IR(0 to 2) is

                    --
                    -- AND Instruction
                    --

                    when opAND =>

                        case IR(3 to 4) is

                            --
                            -- AND, direct, zero page.  Start Read Addr Cycle
                            --  MA <- 00000'IR(5:11)
                            --

                            when amDZ =>
                                maOP      <= maopZP;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateMRIreadAddr;

                            --
                            -- AND, direct, curr page.  Start Read Addr Cycle
                            --  MA <- MA(0:4)'IR(5:11)
                            --

                            when amDC =>
                                maOP      <= maopCP;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateMRIreadAddr;

                            --
                            -- AND, indirect, zero page.  Start Read Addr Cycle
                            --  MA <- 00000'IR(5:11)
                            --

                            when amIZ =>
                                maOP      <= maopZP;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateMRIreadAddr;

                            --
                            -- AND, indirect, curr page.  Start Read Addr Cycle
                            --  MA <- MA(0:4)'IR(5:11)
                            --

                            when amIC =>
                                maOP      <= maopCP;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateMRIreadAddr;

                            --
                            -- Everthing else
                            --

                            when others =>
                                null;

                        end case;

                    --
                    -- TAD Instruction
                    --

                    when opTAD =>

                        case IR(3 to 4) is

                            --
                            -- TAD, direct, zero page.  Start Read Addr Cycle
                            --  MA <- 00000'IR(5:11)
                            --

                            when amDZ =>
                                maOP      <= maopZP;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateMRIreadAddr;

                            --
                            -- TAD, direct, curr page.  Start Read Addr Cycle
                            --  MA <- MA(0:4)'IR(5:11)
                            --

                            when amDC =>
                                maOP      <= maopCP;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateMRIreadAddr;

                            --
                            -- TAD, indirect, zero page.  Start Read Addr Cycle
                            --  MA <- 00000'IR(5:11)
                            --

                            when amIZ =>
                                maOP      <= maopZP;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateMRIreadAddr;

                            --
                            -- TAD, indirect, curr page.  Start Read Addr Cycle
                            --  MA <- MA(0:4)'IR(5:11)
                            --

                            when amIC =>
                                maOP      <= maopCP;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateMRIreadAddr;

                            --
                            -- Everything else
                            --

                            when others =>
                                null;

                        end case;

                    --
                    -- ISZ Instruction
                    --

                    when opISZ =>

                        case IR(3 to 4) is

                            --
                            -- ISZ, direct, zero page.  Start Read Addr Cycle
                            --  MA <- 00000'IR(5:11)
                            --

                            when amDZ =>
                                maOP      <= maopZP;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateMRIreadAddr;

                            --
                            -- ISZ, direct, curr page.  Start Read Addr Cycle
                            --  MA <- MA(0:4)'IR(5:11)
                            --

                            when amDC =>
                                maOP      <= maopCP;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateMRIreadAddr;

                            --
                            -- ISZ, indirect, zero page.  Start Read Addr Cycle
                            --  MA <- 00000'IR(5:11)
                            --

                            when amIZ =>
                                maOP      <= maopZP;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateMRIreadAddr;

                            --
                            -- ISZ, indirect, curr page.  Start Read Addr Cycle
                            --  MA <- MA(0:4)'IR(5:11)
                            --

                            when amIC =>
                                maOP      <= maopCP;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateMRIreadAddr;

                            --
                            -- Everything else
                            --

                            when others =>
                                null;

                        end case;

                    --
                    -- MRI DCA
                    --

                    when opDCA =>

                        case IR(3 to 4) is

                            --
                            -- DCA, direct, zero page.  Start Write Cycle
                            --  MA <- 00000'IR(5:11)
                            --

                            when amDZ =>
                                wrOP      <= '1';
                                acOP      <= acopCLA;
                                maOP      <= maopZP;
                                mbOP      <= mbopAC;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateDone;

                            --
                            -- DCA, direct, curr page.  Start Write Cycle
                            --  MA <- MA(0:4)'IR(5:11)
                            --

                            when amDC =>
                                wrOP      <= '1';
                                acOP      <= acopCLA;
                                maOP      <= maopCP;
                                mbOP      <= mbopAC;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateDone;

                            --
                            -- DCA, indirect, zero page.  Start Read Addr Cycle.
                            --  MA <- 00000'IR(5:11)
                            --

                            when amIZ =>
                                maOP      <= maopZP;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateMRIreadAddr;

                            --
                            -- DCA, indirect, curr page.  Start Read Addr Cycle.
                            --  MA <- MA(0:4)'IR(5:11)
                            --

                            when amIC =>
                                maOP      <= maopCP;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateMRIreadAddr;

                            --
                            -- Everything else
                            --

                            when others =>
                                 null;

                        end case;

                    --
                    -- JMS Instruction
                    --

                    when opJMS =>

                        --
                        -- The II Register is cleared.
                        -- The FZ Register is cleared
                        --

                        iiOP <= iiopCLR;
                        fzOP <= fzopCLR;

                        case IR(3 to 4) is

                            --
                            -- JMS, direct, zero page.  Start write cycle.
                            --  MA <- 00000'IR(5:11)
                            --
                            -- When the PEX Flip-flop is set, the CPU shall
                            -- exit from Panel Mode to Main Memory (i.e., clear
                            -- CTRLFF) during the next JMP, JMS, RTN1 or RTN2
                            -- instruction.
                            --
                            -- PEX is cleared by the JMP, JMS, RTN1 or RTN2
                            -- instruction.
                            --

                            when amDZ =>
                                ifOP      <= ifopIB;
                                ufOP      <= ufopUB;
                                wrOP      <= '1';
                                maOP      <= maopZP;
                                mbOP      <= mbopPC;
                                pcOP      <= pcopZPP1;
                                xmaOP     <= xmaopIB;
                                memselOP  <= '1';
                                busOP     <= busopWRIB;
                                if PEX = '1' then
                                    ctrlffOP <= ctrlffopCLR;
                                    pexOP    <= pexopCLR;
                                end if;
                                nextState <= stateDone;

                            --
                            -- JMS, direct, curr page.  Start write cycle.
                            --  MA <- MA(0:4)'IR(5:11)
                            --
                            -- When the PEX Flip-flop is set, the CPU shall
                            -- exit from Panel Mode to Main Memory (i.e., clear
                            -- CTRLFF) during the next JMP, JMS, RTN1 or RTN2
                            -- instruction.
                            --
                            -- PEX is cleared by the JMP, JMS, RTN1 or RTN2
                            -- instruction.
                            --

                            when amDC =>
                                ifOP      <= ifopIB;
                                ufOP      <= ufopUB;
                                wrOP      <= '1';
                                maOP      <= maopCP;
                                mbOP      <= mbopPC;
                                pcOP      <= pcopCPP1;
                                xmaOP     <= xmaopIB;
                                memselOP  <= '1';
                                busOP     <= busopWRIB;
                                if PEX = '1' then
                                    ctrlffOP <= ctrlffopCLR;
                                    pexOP    <= pexopCLR;
                                end if;
                                nextState <= stateDone;

                            --
                            -- JMS, indirect, zero page.  Start Read Addr Cycle.
                            --  MA <- 00000'IR(5:11)
                            --

                            when amIZ =>
                                maOP      <= maopZP;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateMRIreadAddr;

                            --
                            -- JMS, indirect, curr page.  Start Read Addr Cycle.
                            --  MA <- MA(0:4)'IR(5:11)
                            --

                            when amIC =>
                                maOP      <= maopCP;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateMRIreadAddr;

                            --
                            -- Everthing else
                            --

                            when others =>
                                null;

                        end case;

                    --
                    -- JMP Instruction
                    --

                    when opJMP =>

                        --
                        -- The II Register is cleared.
                        -- The FZ Register is cleared
                        --

                        iiOP <= iiopCLR;
                        fzOP <= fzopCLR;

                        case IR(3 to 4) is

                            --
                            -- JMP, direct, zero page.
                            --  MA <- 00000'IR(5:11)
                            --
                            -- When the PEX Flip-flop is set, the CPU shall
                            -- exit from Panel Mode to Main Memory (i.e., clear
                            -- CTRLFF) during the next JMP, JMS, RTN1 or RTN2
                            -- instruction.
                            --
                            -- PEX is cleared by the JMP, JMS, RTN1 or RTN2
                            -- instruction.
                            --

                            when amDZ =>
                                maOP <= maopZP;
                                pcOP <= pcopZP;
                                ifOP <= ifopIB;
                                ufOP <= ufopUB;
                                if PEX = '1' then
                                    ctrlffOP <= ctrlffopCLR;
                                    pexOP    <= pexopCLR;
                                end if;
                                nextState <= stateDone;

                            --
                            -- JMP, direct, curr page.
                            --  MA <- MA(0:4)'IR(5:11)
                            --
                            -- When the PEX Flip-flop is set, the CPU shall
                            -- exit from Panel Mode to Main Memory (i.e., clear
                            -- CTRLFF) during the next JMP, JMS, RTN1 or RTN2
                            -- instruction.
                            --
                            -- PEX is cleared by the JMP, JMS, RTN1 or RTN
                            -- instruction.
                            --

                            when amDC =>
                                maOP <= maopCP;
                                pcOP <= pcopCP;
                                ifOP <= ifopIB;
                                ufOP <= ufopUB;
                                if PEX = '1' then
                                    ctrlffOP <= ctrlffopCLR;
                                    pexOP    <= pexopCLR;
                                end if;
                                nextState <= stateDone;

                            --
                            -- JMP, indirect, zero page.  Start Read Addr Cycle.
                            --  MA <- 00000'IR(5:11)
                            --

                            when amIZ =>
                                maOP      <= maopZP;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateMRIreadAddr;

                            --
                            -- JMP, indirect, curr page.  Start Read Addr Cycle.
                            --  MA <- MA(0:4)'IR(5:11)
                            --

                            when amIC =>
                                maOP      <= maopCP;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateMRIreadAddr;

                            --
                            -- Everything else
                            --

                            when others =>
                                null;

                        end case;

                    --
                    -- IOT Instructions
                    --

                    when opIOT =>

                        --
                        -- Default Next State
                        --

                        nextState <= stateDone;

                        --
                        -- Handle USR Mode interrupts
                        --

                        if (UF = '1') then

                            usrtrpOP  <= usrtrpopSET;
                            nextState <= stateDone;

                        else

                            --
                            -- Internal IOT (CPU Control)
                            --   600x, 62xx are internal IOTs
                            --

                            case IR(0 to 11) is

                                --
                                -- OP 6000: PRS/SKON
                                --

                                when o"6000" =>

                                    --
                                    -- HD6120 only
                                    -- OP 6000: PRS - Panel Read Status Word.
                                    -- Read panel status bits into AC<0-4>, 0
                                    -- into AC<5:11>.  Following the reading of
                                    -- the flags into the AC, the flags are
                                    -- cleared, with the exception of HLTTRP.
                                    -- BTSTR is cleared only if a 1 was read
                                    -- into AC<0>.
                                    --

                                    if swCPU = swHD6120 then
                                        if CTRLFF = '1' then
                                            acOP     <= acopPRS;
                                            pnltrpOP <= pnltrpopCLR;
                                            pwrtrpOP <= pwrtrpopCLR;
                                            btstrpOP <= btstrpopCLR;
                                        end if;

                                    --
                                    -- PDP-8/E and later and HD-6120
                                    -- SKON - Skip if interupt system is on,
                                    -- turn it off.
                                    --

                                    elsif ((swCPU = swPDP8E) or
                                           (swCPU = swPDP8F) or
                                           (swCPU = swPDP8A) or
                                           (swCPU = swHD6120)) then
                                        if IE = '1' then
                                            pcOP <= pcopINC;
                                        end if;
                                        ieOP <= ieopCLR;

                                    --
                                    -- Pre PDP8/E
                                    -- This instruction was a NOP.
                                    --

                                    else
                                        null;

                                    end if;

                                --
                                -- IOT 6001: ION - Enable Interrupts.
                                -- The Interrupt Enable Register (IE) is set.
                                -- The Interrupt Enable Delay Register (ID)
                                -- is set.
                                --
                                -- Note: Setting the ID delays the interrupt
                                -- enable by one instruction so that a return
                                -- (from interrupt) may be executed before the
                                -- next interrupt request is serviced.
                                --

                                when o"6001" =>
                                    ieOP <= ieopSET;
                                    idOP <= idopSET;

                                --
                                -- IOT 6002: IOF - Disable Interrupts
                                -- The Interrupt Enable Flip Flop (IE) is cleared
                                -- immediately. If IRQ is low while this
                                -- instruction is being processed, the interrupt
                                -- will not be recognized.
                                --

                                when o"6002" =>
                                    ieOP <= ieopCLR;

                                --
                                -- OP 6003: PGO/SRQ
                                --

                                when o"6003" =>

                                    --
                                    -- HD6120 only
                                    -- OP 6003: PGO - Panel Go.
                                    --

                                    if swCPU = swHD6120 then
                                        if CTRLFF = '1' then
                                            hlttrpOP <= hlttrpopCLR;
                                        end if;

                                    --
                                    -- PDP-8/E and later and HD-6120
                                    -- OP 6003: SRQ - Skip on Interupt Request
                                    --

                                    elsif ((swCPU = swPDP8E) or
                                           (swCPU = swPDP8F) or
                                           (swCPU = swPDP8A) or
                                           (swCPU = swHD6120)) then
                                        if IRQ = '1' then
                                            pcOP <= pcopINC;
                                        end if;

                                    --
                                    -- Pre PDP-8/E
                                    -- OP 6003: ION - This was equivalent to
                                    -- the ION instruction.
                                    --

                                    else
                                        ieOP <= ieopSET;
                                        idOP <= idopSET;

                                    end if;

                                --
                                -- IOT 6004: PEX/GTF
                                --
                                -- GTF - Get Flags
                                --
                                --  00 01 02 03 04 05 06 07 08 09 10 11
                                -- +--+--+--+--+--+--+--------+--------+
                                -- | L|GT|IR|0 |IE|UF|   IF   |   DF   |
                                -- +--+--+--+--+--+--+--------+--------+
                                --
                                -- L  - The link bit.
                                -- GT - The Greater Than bit
                                -- IR - The interrupt request status, as tested by SRQ.
                                -- IE - The state of the interrupt enable flip-flop (IE)
                                -- UF - User Flag
                                -- IF - The instruction field.
                                -- DF - The data field.
                                --
                                -- PEX -  Panel Exit to Normal Mode
                                -- Exit from panel mode into main memory at the end
                                -- of the next JMP, JMS, RTN1 or RTN2 instruction.
                                --

                                when o"6004" =>

                                    --
                                    -- OP 6004: PEX - Panel Exit to Normal Mode
                                    -- HD6120 in Panel Mode only
                                    --
                                    -- Set PEX Flip-flop
                                    -- Clear PWRTRP and PNLTRP.
                                    --

                                    if swCPU = swHD6120 and CTRLFF = '1' then
                                        pwrtrpOP <= pwrtrpopCLR;
                                        pnltrpOP <= pnltrpopCLR;
                                        pexOP    <= pexopSET;

                                    --
                                    -- OP 6004: GTF - Get Flags
                                    -- HD6120 in Normal Mode only
                                    -- AC(4) is always set.
                                    -- AC(5) is always cleared.
                                    --

                                    elsif swCPU = swHD6120 and CTRLFF = '0' then
                                        acOP <= acopGTF1;

                                    --
                                    -- OP 6004: GTF - Get Flags
                                    -- PDP-8/E and later with KM8E installed
                                    -- AC(4) is set to state of the interrupt
                                    --

                                    elsif ((swCPU = swPDP8E and swOPT.KM8E = '1') or
                                           (swCPU = swPDP8F and swOPT.KM8E = '1') or
                                           (swCPU = swPDP8A and swOPT.KM8E = '1')) then
                                        acOP <= acopGTF2;

                                    --
                                    -- Pre PDP-8/E
                                    -- OP 6004: This was and ADC operation or a
                                    -- NOP.
                                    --

                                    else
                                        null;

                                    end if;

                                --
                                -- IOT 6005: RTF - Restore Flags and Fields from AC.
                                -- The flags are set as follows:
                                --
                                --  00 01 02 03 04 05 06 07 08 09 10 11
                                -- +--+--+--+--+--+--+--------+--------+
                                -- | L|GT|  |  |IE|UB|   IB   |   DF   |
                                -- +--+--+--+--+--+--+--------+--------+
                                --

                                when o"6005" =>
                                    if ((swCPU = swPDP8E) or
                                        (swCPU = swPDP8F) or
                                        (swCPU = swPDP8A) or
                                        (swCPU = swHD6120)) then

                                        --
                                        -- HD6120: The AC is cleared following
                                        -- the load operation.  The interrupt
                                        -- is enabled per AC(4).  See HD6120
                                        -- GTF instruction.
                                        --

                                        if swCPU = swHD6120 then

                                            if AC(0) = '1' then
                                                acOP <= acopCLACLLCML;
                                            else
                                                acOP <= acopCLACLL;
                                            end if;

                                            if AC(4) = '1' then
                                                ieOP <= ieopSET;
                                                iiOP <= iiopSET;
                                            end if;

                                        --
                                        -- PDP8/E and later: AC is not modified by
                                        -- the instruction. AC(4) is ignored and
                                        -- interrupts are unconditionally
                                        -- re-enabled.  AC(5) sets the UB bit.
                                        -- See PDP/8 GTF instruction.
                                        --

                                        else

                                            if AC(0) = '1' then
                                                acOP <= acopCLLCML;
                                            else
                                                acOP <= acopCLL;
                                            end if;
                                            ieOP <= ieopSET;
                                            iiOP <= iiopSET;
                                            ubOP <= ubopAC5;
                                        end if;

                                        gtfOP <= gtfopAC1;
                                        ibOP  <= ibopAC6to8;
                                        dfOP  <= dfopAC9to11;
                                        fzop  <= fzopCLR;

                                    --
                                    -- Pre PDP8/E
                                    -- OP 6005: ION ORed with ADC
                                    --

                                    else
                                        ieOP <= ieopSET;
                                        idOP <= idopSET;

                                    end if;

                                --
                                -- OP 6006: SGT
                                --

                                when o"6006" =>

                                    --
                                    -- PDP8/E and later
                                    -- OP 6006: SGT - Skip if the GT flag is set.
                                    --

                                    if ((swCPU = swPDP8E) or
                                        (swCPU = swPDP8F) or
                                        (swCPU = swPDP8A) or
                                        (swCPU = swHD6120)) then
                                        if GTF = '1' then
                                            pcOP <= pcopINC;
                                        end if;

                                    --
                                    -- Pre PDP8/E
                                    -- OP 6006: This was equivalent to an IOF
                                    -- ORed with and ADC op
                                    --

                                    else
                                        ieOP <= ieopCLR;

                                    end if;

                                --
                                -- OP 6007: CAF - Clear all flags.
                                --

                                when o"6007" =>

                                    --
                                    -- PDP8/E and Later
                                    -- IOT 6007: CAF - Clear all flags.
                                    -- The AC, LINK and GT flag are cleared.
                                    -- Interrupt Enable Flip Flop (IE) is cleared.
                                    -- IOCLR is generated with LXDAR high, causing
                                    -- peripheral devices to clear their flags.
                                    --

                                    if ((swCPU = swPDP8E) or
                                        (swCPU = swPDP8F) or
                                        (swCPU = swPDP8A) or
                                        (swCPU = swHD6120)) then
                                        ioclrOP   <= '1';
                                        lxdarOP   <= '1';
                                        datafOP   <= '1';
                                        gtfOP     <= gtfopCLR;
                                        acOP      <= acopCLACLL;
                                        emodeOP   <= emodeopCLR;
                                        ieOP      <= ieopCLR;
                                        idOP      <= idopSET;
                                        busOP     <= busopIOCLR;
                                        usrtrpOP  <= usrtrpopCLR;

                                    --
                                    -- Pre PDP8/E
                                    -- OP 6007: ION ORed with ADC
                                    --

                                    else
                                        ieOP <= ieopSET;
                                        idOP <= idopSET;

                                    end if;

                                --
                                -- IOT 6200: LXM - Load Extended Mode Register
                                -- On all machines without KT8-A this is executed
                                -- as a NOP instruction.
                                --

                                when o"6200" =>
                                    null;

                                --
                                -- IOT 62x1: CDF - Change Data Field
                                -- The Data Field Register (DF) is loaded with IR<6:8>
                                -- of this instruction.
                                --

                                when o"6201" | o"6211" | o"6221" | o"6231" | o"6241" | o"6251" | o"6261" | o"6271" =>
                                    dfOP <= dfopIR6to8;

                                --
                                -- IOT 62x2: CIF - Change Instruction Field
                                -- The Instruction Buffer (IB/IB) is loaded with
                                -- IR<6:8> of this instruction and the Interrupt
                                -- Inhibit Flip Flop (II) is set.
                                --
                                -- Note: Setting the II causes the CPU to ignore
                                -- interrupt requests until the next JMP, JMS,
                                -- RTN1 or RTN2 Instruction is executed.  At that
                                -- time the contents of IB/IB are loaded into the
                                -- IF/INF and the II cleared.
                                --

                                when o"6202" | o"6212" | o"6222" | o"6232" | o"6242" | o"6252" | o"6262" | o"6272" =>
                                    ibOP <= ibopIR6to8;
                                    iiOP <= iiopSET;
                                    fzop <= fzopCLR;

                                --
                                -- IOT 62x2: CIF/CDF (CDI) - Change Instruction
                                -- and Data Field.
                                -- A microprogrammed combination of CDF and CIF.
                                -- Both fields are set to X.
                                --

                                when o"6203" | o"6213" | o"6223" | o"6233" | o"6243" | o"6253" | o"6263" | o"6273" =>
                                    dfOP <= dfopIR6to8;
                                    ibOP <= ibopIR6to8;
                                    iiOP <= iiopSET;
                                    fzop <= fzopCLR;

                                --
                                -- IOT 6204: CINT - Clear User Interrupt Flag
                                --

                                when o"6204" =>
                                    usrtrpOP <= usrtrpopCLR;

                                --
                                -- IOT 6205: PPC1 - Push (PC+1) to Stack 1
                                -- The contents of the PC are incremented by
                                -- one and the result is loaded into the memory
                                -- location pointed to by the contents of SP1.
                                -- SP1 is then decremented by 1.
                                --
                                -- The stacks are located in field 0 of memory.
                                --

                                when o"6205" =>
                                    if swCPU = swHD6120 then
                                        wrOP     <= '1';
                                        maOP     <= maopSP1;
                                        mbOP     <= mbopPCP1;
                                        sp1OP    <= spopDEC;
                                        xmaOP    <= xmaopCLR;
                                        memselOP <= '1';
                                        busOP    <= busopWRZF;
                                    end if;

                                --
                                -- IOT 6206: PR0 - Panel Request 0
                                -- The PNLTRP flag is set.  If the Interrupt Inhibit
                                -- Register (ION) is not set, the CPU will enter
                                -- panel mode instead of executing the next
                                -- instruction.  If the Interrupt Inhibit Flip Flop
                                -- is set, panel mode will be entered following the
                                -- next JMP, JMS, RTN1 or RTN2 which clears the
                                -- Interrupt inhibit flip flop.  This is a NOP in
                                -- panel mode.
                                --

                                when o"6206" =>
                                    if swCPU = swHD6120 then
                                        if CTRLFF = '0' then
                                            pnltrpOP <= pnltrpopSET;
                                        end if;
                                    end if;

                                --
                                -- IOT 6207: RSP1 - Read Stack 1 Pointer to AC
                                -- The contents of SP1 is loaded Into the AC.
                                --

                                when o"6207" =>
                                    if swCPU = swHD6120 then
                                        acOP <= acopSP1;
                                    end if;

                                --
                                -- IOT 6214: RDF - Read Data Field to AC<6:8>
                                -- PDP8: The RDF ors the DF register with AC<6:8>.
                                -- HD6120: The RDF replaces AC<6:8> with DF<0:2>.
                                -- The other bits of the accumulator are unaffected
                                --

                                when o"6214" =>
                                    if swCPU = swHD6120 then
                                        acOP <= acopRDF0;
                                    else
                                        acOP <= acopRDF1;
                                    end if;

                                --
                                -- IOT 6215: PAC1 - Push AC to Stack 1.
                                -- The contents of the AC is loaded into the
                                -- memory location pointed to by the contents
                                -- of SP1. The contents of SP1 is then
                                -- decremented by 1.
                                --
                                -- The stacks are located in field 0 of memory.
                                --

                                when o"6215" =>
                                    if swCPU = swHD6120 then
                                        wrOP     <= '1';
                                        maOP     <= maopSP1;
                                        mbOP     <= mbopAC;
                                        sp1OP    <= spopDEC;
                                        xmaOP    <= xmaopCLR;
                                        memselOP <= '1';
                                        busOP    <= busopWRZF;
                                    end if;

                                --
                                -- IOT 6216: PR1 - Panel Request 1.
                                -- The PNLTRP flag is set.  If the Interrupt Inhibit
                                -- Register (ION) is not set, the CPU will enter
                                -- panel mode instead of executing the next
                                -- instruction.  If the Interrupt Inhibit Flip Flop
                                -- is set, panel mode will be entered following the
                                -- next JMP, JMS, RTN1 or RTN2 which clears the
                                -- Interrupt inhibit flip flop.  This is a NOP in
                                -- panel mode.
                                --

                                when o"6216" =>
                                    if swCPU = swHD6120 then
                                        if CTRLFF = '0' then
                                            pnltrpOP  <= pnltrpopSET;
                                        end if;
                                    end if;

                                --
                                -- IOT 6217: LSP1 - Load Stack 1 Pointer from AC.
                                -- The contents of the AC is loaded into SP1.
                                -- The AC is cleared.
                                --

                                when o"6217" =>
                                    if swCPU = swHD6120 then
                                        sp1OP <= spopAC;
                                        acOP  <= acopCLA;
                                    end if;

                                --
                                -- IOT 6224: RIF - Read Instruction Field into AC<6:8>.
                                -- PDP8: The RIF ors the IF/INF register with AC<6:8>.
                                -- HD6120: The RIF replaces AC<6:8> with IF/INF<0:2>.
                                -- The other bits of the accumulator are unaffected
                                --

                                when o"6224" =>
                                    if swCPU = swHD6120 then
                                        acOP <= acopRIF0;
                                    else
                                        acOP <= acopRIF1;
                                    end if;

                                --
                                -- IOT 6225: RTN1 - Pop top of Stack 1 to PC
                                --
                                -- The contents of the stack pointer (SP1) is
                                -- incremented by one.  The contents of the
                                -- memory location pointed to by SP1 is loaded
                                -- into the PC.
                                --

                                when o"6225" =>
                                    if swCPU = swHD6120 then
                                        sp1OP     <= spopINC;
                                        nextState <= stateRTN1;
                                    end if;

                                --
                                -- IOT 6226: PR2 - Panel Request 2.
                                -- The PNLTRP flag is set.  If the Interrupt Inhibit
                                -- Register (ION) is not set, the CPU will enter
                                -- panel mode instead of executing the next
                                -- instruction.  If the Interrupt Inhibit Flip Flop
                                -- is set, panel mode will be entered following the
                                -- next JMP, JMS, RTN1 or RTN2 which clears the
                                -- Interrupt inhibit flip flop.  This is a NOP in
                                -- panel mode.
                                --

                                when o"6226" =>
                                    if swCPU = swHD6120 then
                                        if CTRLFF = '0' then
                                            pnltrpOP <= pnltrpopSET;
                                        end if;
                                    end if;

                                --
                                -- IOT 6227: RSP2 - Read Stack 2 Pointer to AC
                                -- The contents of SP2 is loaded Into the AC.
                                --

                                when o"6227" =>
                                    if swCPU = swHD6120 then
                                        acOP <= acopSP2;
                                    end if;

                                --
                                -- IOT 6234: RIB - Read Instruction Save Field into AC<6:8>
                                -- and Data Save Field into AC<9:11>.
                                -- PDP8: The RIB ors the ISF/DSF register with AC<6:11>.
                                -- HD6120: The RIB replaces AC<6:11> with ISF/DSF.
                                -- The other bits of the accumulator are unaffected
                                --

                                when o"6234" =>
                                    if swCPU = swHD6120 then
                                        acOP <= acopRIB0;
                                    else
                                        acOP <= acopRIB1;
                                    end if;

                                --
                                -- IOT 6235: POP1 - Pop top of Stack 1 to AC
                                -- The contents of SP1 is incremented by 1. The
                                -- contents of the memory location pointed to
                                -- by SP1 is then loaded into the AC.
                                --
                                -- The stacks are located in field 0 of memory.
                                --

                                when o"6235" =>
                                    if swCPU = swHD6120 then
                                        maOP      <= maopSP1P1;
                                        sp1OP     <= spopINC;
                                        xmaOP     <= xmaopCLR;
                                        memselOP  <= '1';
                                        busOP     <= busopRDZFaddr;
                                        nextState <= statePOPaddr;
                                    end if;

                                --
                                -- IOT 6236: PR3 - Panel Request 3.
                                -- The PNLTRP flag is set.  If the Interrupt Inhibit
                                -- Register (ION) is not set, the CPU will enter
                                -- panel mode instead of executing the next
                                -- instruction.  If the Interrupt Inhibit Flip Flop
                                -- is set, panel mode will be entered following the
                                -- next JMP, JMS, RTN1 or RTN2 which clears the
                                -- Interrupt inhibit flip flop.  This is a NOP in
                                -- panel mode.
                                --

                                when o"6236" =>
                                    if swCPU = swHD6120 then
                                        if CTRLFF = '0' then
                                            pnltrpOP <= pnltrpopSET;
                                        end if;
                                    end if;

                                --
                                -- IOT 6237: LSP2 - Load Stack 2 Pointer from AC.
                                -- The contents of the AC is loaded into SP2.
                                -- The AC is cleared.
                                --

                                when o"6237" =>
                                    if swCPU = swHD6120 then
                                        sp2OP <= spopAC;
                                        acOP  <= acopCLA;
                                    end if;

                                --
                                -- IOT 6244: RMF - Restore Memory Fields.
                                -- Load the contents of ISF into IB, OSF into OF,
                                -- and set the Interrupt Inhibit Flip Flop. This instruction
                                -- is used to restore the contents of the memory
                                -- field registers to their values before an
                                -- interrupt occurred.
                                --
                                -- Note: Setting the II causes the CPU to ignore
                                -- interrupt requests until the next JMP, JMS,
                                -- RTN1 or RTN2 Instruction is executed.  At that
                                -- time the contents of IB are loaded into the
                                -- IF/INF and the II cleared.
                                --

                                when o"6244" =>
                                    ubOP <= ubopSF;
                                    ibOP <= ibopSF1to3;
                                    dfOP <= dfopSF4to6;
                                    iiOP <= iiopSET;
                                    fzop <= fzopCLR;

                                --
                                -- IOT 6245: PPC2 - Push (PC+1) to Stack 2
                                -- The contents of the PC are Incremented by
                                -- one and the result is loaded into the memory
                                -- location pointed to by the contents of SP2.
                                -- SP2 is then decremented by 1.
                                --
                                -- The stacks are located in field 0 of memory.
                                --

                                when o"6245" =>
                                    if swCPU = swHD6120 then
                                        wrOP     <= '1';
                                        maOP     <= maopSP2;
                                        mbOP     <= mbopPCP1;
                                        sp2OP    <= spopDEC;
                                        xmaOP    <= xmaopCLR;
                                        memselOP <= '1';
                                        busOP    <= busopWRZF;
                                    end if;

                                --
                                -- IOT 6246: WSR - Write to Switch Register
                                -- The contents of AC are written to the switch
                                -- register and the AC is cleared.  This allows
                                -- the switch register to be 'virtualized' in
                                -- from panel mode for units without front panel
                                -- interfaces.
                                --

                                when o"6246" =>
                                    if swCPU = swHD6120 then
                                        srOP <= sropAC;
                                        acOP <= acopCLA;
                                    end if;

                                --
                                -- IOT 6254: SINT - Skip on User Interrupt Flag
                                --

                                when o"6254" =>
                                    if USRTRP = '1' then
                                        pcOP <= pcopINC;
                                    end if;

                                --
                                -- IOT 6255: PAC2 - Push AC to Stack 2.
                                -- The contents of the AC is loaded into the
                                -- memory location pointed to by the contents
                                -- of SP2. The contents of SP2 is then
                                -- decremented by 1.
                                --
                                -- The stacks are located in field 0 of memory.
                                --

                                when o"6255" =>
                                    if swCPU = swHD6120 then
                                        wrOP     <= '1';
                                        maOP     <= maopSP2;
                                        mbOP     <= mbopAC;
                                        sp1OP    <= spopDEC;
                                        xmaOP    <= xmaopCLR;
                                        memselOP <= '1';
                                        busOP    <= busopWRZF;
                                    end if;

                                --
                                -- IOT 6256: GCF
                                -- Get current fields and flags
                                --

                                when o"6256" =>
                                    acOP <= acopGCF;

                                --
                                -- IOF 6264: CUF - Clear User Flag
                                -- The CUF instruction clears the User Flag (UF) and
                                -- sets the Interrupt Inhibit Register (II).
                                --

                                when o"6264" =>
                                    ubOP <= ubopCLR;
                                    iiOP <= iiopSET;

                                --
                                -- IOT 6265: RTN2 - Pop top of Stack 2 to PC
                                --
                                -- The contents of the stack pointer (SP2) is
                                -- incremented by one.  The contents of the
                                -- memory location pointed to by SP2 is loaded
                                -- into the PC.
                                --

                                when o"6265" =>
                                    if swCPU = swHD6120 then
                                        sp2op     <= spopINC;
                                        nextState <= stateRTN2;
                                    end if;

                                --
                                -- IOT 6266: CPD - Clear Panel Data Flag
                                -- Clears the Panel Data Flag (PDF) so that indirect
                                -- data operands of panel mode instructions are
                                -- obtained from main memory.
                                --

                                when o"6266" =>
                                    if swCPU = swHD6120 then
                                        if CTRLFF = '1' then
                                            pdfOP <= pdfopCLR;
                                        end if;
                                    end if;

                                --
                                -- IOT 6274: SUF - Set User Flag
                                -- The SUF instruction sets the User Flag (UF) and
                                -- sets the Interrupt Inhibit Flip Flop (II).
                                --

                                when o"6274" =>
                                    ubOP <= ubopSET;
                                    iiOP <= iiopSET;

                                --
                                -- IOT 6275: POP2 - Pop top of Stack 2 to AC
                                -- The contents of SP2 is incremented by 1. The contents
                                -- of the memory location pointed to by SP2 is then
                                -- loaded into the AC.
                                --
                                -- The stacks are located in field 0 of memory.
                                --

                                when o"6275" =>
                                    if swCPU = swHD6120 then
                                        maOP      <= maopSP2P1;
                                        sp2OP     <= spopINC;
                                        xmaOP     <= xmaopCLR;
                                        memselOP  <= '1';
                                        busOP     <= busopRDZFaddr;
                                        nextState <= statePOPaddr;
                                     end if;

                                --
                                -- IOT 6276: SPD - Set Panel Data Flag
                                -- Sets the Panel Data Flag (PDF) so that indirect
                                -- data operands of panel mode instructions are
                                -- obtained from panel memory.
                                --

                                when o"6276" =>
                                    if swCPU = swHD6120 then
                                        if CTRLFF = '1' then
                                            pdfOP <= pdfopSET;
                                        end if;
                                    end if;

                                --
                                -- Unhandled IOTs
                                --

                                when others =>

                                    if (IR(0 to 8) = o"600") or (IR(0 to 5)  = o"62") then

                                        --
                                        -- Internal IOTS (600x and 62xx) that are
                                        -- not handled above.
                                        --

                                        assert false report "Unhandled Internal IOT" severity warning;
                                        nextState <= stateLaLa;

                                    else

                                        --
                                        -- External IOTS.  Handled by external
                                        -- devices.
                                        --

                                        wrOP      <= '1';
                                        datafOP   <= '1';
                                        lxdarOP   <= '1';
                                        maOP      <= maopIR;
                                        mbOP      <= mbopAC;
                                        busOP     <= busopWRIOT;
                                        nextState <= stateIOTdecode;

                                    end if;
                            end case;
                        end if;

                    --
                    -- Operate Instructions
                    --

                    when opOPR =>

                        if IR(3) = '0' then

                            --
                            -- Operate Group 1
                            --
                            --                        Group 1
                            --  |           |           |           |           |
                            --  |---|---|---|---|---|---|---|---|---|---|---|---|
                            --  | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10| 11|
                            --  | 1 | 1 | 1 | 0 |CLA|CLL|CMA|CML| R1| R2| R3|IAC|
                            --  |---|---|---|---|---|---|---|---|---|---|---|---|
                            --                    |   |   |   |   |   |   |   |
                            --        Sequence:   1   1   2   2   4   4   4   3
                            --
                            --

                            --
                            -- Operate Group 1 Sequence 1 and Sequence 2
                            -- This state executes all combinations of Sequence 1
                            -- and Sequence 2 operations
                            --

                            case IR(4 to 7) is

                                --
                                -- OP 7000: NOP
                                --

                                when "0000" =>
                                    null;

                                --
                                -- OP 7020: CML - Complement Link Register
                                -- The contents of the LINK is complemented.
                                --

                                when "0001" =>
                                    acop <= acopCML;

                                --
                                -- OP 7040: CMA - Complement accumulator.
                                -- The contents of the AC is replaced by its
                                -- 1's  complement.
                                --

                                when "0010" =>
                                    acop <= acopCMA;

                                --
                                -- OP 7060: CMA CML
                                -- The contents of the LINK is complemented.
                                -- The contents of the AC is replaced by its
                                -- 1's complement.

                                when "0011" =>
                                    acOP <= acopCMACML;

                                --
                                -- OP 7100: CLL - Clear LINK
                                -- The LINK is set to zero.
                                --

                                when "0100" =>  -- CLL
                                    acOP <= acopCLL;

                                --
                                -- OP 7120: CLL CML (STL) - Set LINK.
                                -- Clear LINK then Complement LINK.  The LINK
                                -- is set to one.
                                --

                                when "0101" =>
                                    acop <= acopCLLCML;

                                --
                                -- OP 7140: CLL CMA -
                                -- Clear LINK and Complement accumulator,
                                --

                                when "0110" =>
                                    acOP <= acopCLLCMA;
                                --
                                -- OP 7160: CLL CMA CML - STL CMA
                                -- Set LINK and Complement accumulator,
                                --

                                when "0111" =>
                                    acOP <= acopCLLCMACML;

                                --
                                -- OP 7200: CLA - Clear accumulator
                                -- Load AC with "0000".
                                --

                                when "1000" =>
                                    acOP <= acopCLA;

                                --
                                -- OP 7220: CLA CML
                                -- Clear Accumulator and Complement LINK
                                --

                                when "1001" =>
                                    acOP <= acopCLACML;

                                --
                                -- OP 7240: CLA CMA (STA)
                                -- Clear Accumulator then Complement
                                -- Accumulator, or Set Accumulator.
                                --

                                when "1010" =>
                                    acOP <= acopCLACMA;

                                --
                                -- OP 7260: CLA CMA CML (STA CML)
                                -- Set Accumulator and Complement LINK.
                                --

                                when "1011" =>
                                    acOP <= acopCLACMACML;

                                --
                                -- OP 7300: CLA CLL
                                -- Clear AC and Clear LINK.
                                --

                                when "1100" =>
                                    acOP <= acopCLACLL;

                                --
                                -- OP 7320: CLA CLL CML
                                -- Clear AC and Set LINK
                                --

                                when "1101" =>
                                    acOP <= acopCLACLLCML;

                                --
                                -- OP 7340: CLA CLL CMA, STA CLL
                                -- Set Accumulator and Clear LINK
                                --

                                when "1110" =>
                                    acOP <= acopCLACLLCMA;

                                --
                                -- OP 7360: CLA CLL CMA CML, STA STL
                                -- Set Accumulator and Set LINK
                                --

                                when "1111" =>
                                    acOP <= acopCLACLLCMACML;

                                --
                                -- Everything else
                                --

                                when others =>
                                    null;

                            end case;

                            --
                            -- Determine the next state.  Skip states if
                            -- possible.
                            --

                            if IR(11) = '1' then
                                nextState <= stateOprGroup1Seq3;
                            else
                                if IR(8) = '1' or IR(9) = '1' or IR(10) = '1' then
                                    nextState <= stateOprGroup1Seq4;
                                else
                                    nextState <= stateDone;
                                end if;
                            end if;

                        else    -- IR(3) = '1'

                            if IR(11) = '0' then

                                --
                                -- Operate Group 2
                                --
                                --                        Group 2
                                --  |           |           |           |           |
                                --  |---|---|---|---|---|---|---|---|---|---|---|---|
                                --  | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10| 11|
                                --  | 1 | 1 | 1 | 1 |CLA|SMA|SZA|SNL| 0 |OSR|HLT| 0 |
                                --  | 1 | 1 | 1 | 1 |CLA|SPA|SNA|SZL| 1 |OSR|HLT| 0 |
                                --  |---|---|---|---|---|---|---|---|---|---|---|---|
                                --                    |   |   |   |       |   |
                                --        Sequence:   2   1   1   1       3   3
                                --
                                --

                                --
                                -- This state handles Operating Group 2
                                -- Sequence 1
                                --

                                case IR(5 to 8) is

                                    --
                                    -- OP 7400: NOP
                                    --

                                    when "0000" =>
                                        null;

                                    --
                                    -- OP 7410: SKP - SKIP
                                    -- The content of the PC is incremented by 1,
                                    -- to skip the next Instruction.
                                    --

                                    when "0001" =>
                                        pcop <= pcopINC;

                                    --
                                    -- OP 7420: SNL
                                    -- Skip if LINK = 1
                                    --

                                    when "0010" =>
                                        if L = '1' then
                                            pcop <= pcopINC;
                                        end if;

                                    --
                                    -- OP 7430: SZL
                                    -- Skip if LINK = 0
                                    --

                                    when "0011" =>
                                        if L = '0' then
                                            pcop <= pcopINC;
                                        end if;

                                    --
                                    -- OP 7440: SZA
                                    -- Skip on zero accumulator (AC = "0000")
                                    --

                                    when "0100" =>
                                        if AC = o"0000" then
                                            pcop <= pcopINC;
                                        end if;

                                    --
                                    -- OP 7450: SNA
                                    -- Skip on non-zero accumulator
                                    --

                                    when "0101" =>
                                        if AC /= o"0000" then
                                            pcop <= pcopINC;
                                        end if;

                                    --
                                    -- OP 7460: SZA SNL
                                    -- Skip if AC="0000" or if LINK = 1
                                    --

                                    when "0110" =>
                                        if ((AC = o"0000") or (L = '1')) then
                                            pcop <= pcopINC;
                                        end if;

                                    --
                                    -- OP 7470: SNA SZL
                                    -- Skip if AC not "0000" and if LINK = 1
                                    --

                                    when "0111" =>
                                        if ((AC /= o"0000") and (L = '0')) then
                                            pcop <= pcopINC;
                                        end if;

                                    --
                                    -- OP 7500: SMA
                                    -- Skip on negative (minus) accumulator (AC0=1)
                                    --

                                    when "1000" =>
                                        if AC(0) = '1' then
                                            pcop <= pcopINC;
                                        end if;

                                    --
                                    -- OP 7510: SPA
                                    -- Skip on positive accumulator (AC0=0)
                                    --

                                    when "1001" =>
                                        if AC(0) = '0' then
                                            pcop <= pcopINC;
                                        end if;

                                    --
                                    -- OP 7520: SMA SNL
                                    -- Skip if AC is negative (minus) or if LINK is 1
                                    --

                                    when "1010" =>
                                        if ((AC(0) = '1') or (L = '1')) then
                                            pcop <= pcopINC;
                                        end if;

                                    --
                                    -- OP 7530: SPA SZL
                                    -- Skip if AC is positive and if LINK is 0
                                    --

                                    when "1011" =>
                                        if ((AC(0) = '0') and (L = '0')) then
                                            pcop <= pcopINC;
                                        end if;

                                    --
                                    -- OP 7540: SMA SZA - Skip if AC is minus or zero
                                    --

                                    when "1100" =>
                                        if ((AC(0) = '1') or (AC = o"0000")) then
                                            pcop <= pcopINC;
                                        end if;

                                    --
                                    -- OP 7550: SPA SNA
                                    -- Skip if AC is positive and non-zero
                                    --

                                    when "1101" =>
                                        if ((AC(0) = '0') and (AC /= o"0000")) then
                                            pcop <= pcopINC;
                                        end if;

                                    --
                                    -- OP 7560: SMA SZA SNL
                                    -- Skip if AC is minus or if AC="0000" or if LINK is 1
                                    --

                                    when "1110" =>
                                        if ((AC(0) = '1') or (AC = o"0000") or (L = '1')) then
                                            pcop <= pcopINC;
                                        end if;

                                    --
                                    -- OP 7570: SPA SNA SZL
                                    -- Skip if AC is positive, nonzero, and if LINK is zero.
                                    --

                                    when "1111" =>
                                        if ((AC(0) = '0') and (AC /= o"0000") and (L = '0')) then
                                            pcop <= pcopINC;
                                        end if;

                                    --
                                    -- Everything else
                                    --

                                    when others =>
                                        null;

                                end case;

                                --
                                -- Determine if there are any Group 2 Sequence
                                -- 2 operations to perform.  Skip states if not.
                                --

                                if IR(4) = '1' or IR(9) = '1' or IR(10) = '1' then
                                    nextState <= stateOprGroup2Seq2;
                                else
                                    nextstate <= stateDone;
                                end if;

                            else  -- IR(11) = '1'

                                --
                                --
                                -- Decode Group 3 Sequence 1,2 Opcode
                                --
                                --                        Group 3
                                --  |           |           |           |           |
                                --  |---|---|---|---|---|---|---|---|---|---|---|---|
                                --  | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10| 11|
                                --  | 1 | 1 | 1 | 1 |CLA|MQA| 0 |MQL| 0 | 0 | 0 | 1 |
                                --  |---|---|---|---|---|---|---|---|---|---|---|---|
                                --                    |   |       |
                                --        Sequence:   1   2       2
                                --
                                -- Note: In the state machine, Sequence 1 and Sequence 2
                                -- are handled together to save time (cycles).
                                --
                                -- Operate Group 3, 3A and 3B instructions.
                                --
                                -- HD6120: If bits 6, 8, 9 or 10 are set to a
                                -- one, instruction execution is not altered but the
                                -- instruction becomes uninterruptable by either
                                -- panel or normal interrupts.  That is, the next
                                -- instruction is guaranteed to be fetched barring
                                -- a reset, DMAREQ or RUN/HLT flip flop in the
                                -- HLT state.
                                --

                                if ((swCPU = swHD6120 and IR( 6) = '1') or
                                    (swCPU = swHD6120 and IR( 8) = '1') or
                                    (swCPU = swHD6120 and IR( 9) = '1') or
                                    (swCPU = swHD6120 and IR(10) = '1')) then
                                    idOP <= idopSET;
                                end if;

                                --
                                -- OP 74x1: EAE Instructions
                                --
                                -- The PDP8/L had no provision for EAE
                                --
                                -- These instructions were only available pre
                                -- PDP8/E if EAE was added.
                                --
                                -- These instruction work on PDP8/E and later
                                -- with or without EAE.
                                --

                                if ((swCPU = swPDP8  and swOPT.KE8 = '1') or
                                    (swCPU = swPDP8S and swOPT.KE8 = '1') or
                                    (swCPU = swPDP8I and swOPT.KE8 = '1') or
                                    -- PDP8L never supported EAE
                                    (swCPU = swPDP8E) or
                                    (swCPU = swPDP8F) or
                                    (swCPU = swPDP8M) or
                                    (swCPU = swPDP8A) or
                                    (swCPU = swHD6120)) then

                                    EAEIR := IR(4) & IR(5) & IR(7) & '0';
                                    case EAEIR(0 to 2) is

                                        --
                                        -- OP 7401: NOP
                                        --

                                        when "000" =>
                                            null;

                                        --
                                        -- OP 7421: MQL - MQ register load
                                        -- The MQ is loaded with the contents of the
                                        -- AC and the AC is cleared. The original
                                        -- contents of the MQ is lost.
                                        --

                                        when "001" =>
                                            mqOP <= mqopAC;
                                            acOP <= acopCLA;

                                        --
                                        -- OP 7501: MQA - MQ "OR" with accumulator.
                                        -- OR the contents of the MQ is "OR"ed with
                                        -- the contents of the AC, and the result left
                                        -- in the AC.  The MQ is not modified.
                                        --

                                        when "010" =>
                                            acOP <= acopORMQ;

                                        --
                                        -- OP 7521: SWP - Swap contents of AC and MQ.
                                        -- The contents of the AC and MQ are exchanged
                                        --
                                        -- The SWP instruction does not work on
                                        -- Straight 8 (PDP8)

                                        when "011" =>
                                            if ((swCPU = swPDP8) or
                                                (swCPU = swPDP8I)) then
                                                -- What should this do?
                                                acOP <= acopNOP;
                                                mqOP <= mqopNOP;
                                            else
                                                acOP <= acopMQ;
                                                mqOP <= mqopAC;
                                            end if;

                                        --
                                        -- OP 7601: CLA - Clear Accumulator
                                        -- The accumulator may be cleared prior to other
                                        -- group three microcoded operations. Unless
                                        -- microcoded with other group three instructions,
                                        -- PDP-8 assemblers generally assume that the CLA
                                        -- mnemonic refers to the group one instruction.
                                        --

                                        when "100" =>
                                            acOP <= acopCLA;

                                        --
                                        -- OP 7621: CLA/MQL - CAM - Clear AC and MQ
                                        -- This instruction first clears AC, so the
                                        -- result is to clear both AC and MQ.
                                        --

                                        when "101" =>
                                            acOP <= acopCLA;
                                            mqOP <= mqopCLR;

                                        --
                                        -- OP 7701: CLA MQA - ACL - Microcode CLA MQA
                                        -- This instruction first clears AC, so the
                                        -- result is to load AC with the contents
                                        -- of MQ.
                                        --

                                        when "110" =>
                                            acOP <= acopMQ;

                                        --
                                        -- OP 7721: CLA SWP - Clear AC, then swap.
                                        -- The MQ is loaded into the AC;
                                        -- "0000" is loaded into the MQ.
                                        --

                                        when "111" =>
                                            acOP <= acopMQ;
                                            mqOP <= mqopCLR;

                                        --
                                        -- Everything else
                                        --

                                        when others =>
                                            null;

                                    end case;

                                    --
                                    -- Group 3 Sequence 3 instruction are
                                    -- supported with EAE installed.
                                    --

                                    if swOPT.KE8 = '1' then
                                        nextState <= stateOprGroup3Seq3;
                                    else
                                        nextstate <= stateDone;
                                    end if;

                                end if;  -- Group 3
                            end if;  -- IR(11)
                        end if;  -- IR(3)

                    --
                    -- Everything else
                    --

                    when others =>
                        null;

                end case;

            --
            -- IOT Decode State
            -- The previous state peformed an IOT write cycle.  This state
            -- decides the devc and skip that is return by the IOT interface.
            --

            when stateIOTdecode =>

                --
                -- Handle Skip
                --

                if dev.skip = '1' then
                    pcOP <= pcopINC;
                end if;

                --
                -- Handle CLA
                --

                if dev.devc = devWRCLR or dev.devc = devRDCLR then
                    acOP <= acopCLA;
                end if;

                --
                -- Handle RD and WR
                --

                if dev.devc = devRD or dev.devc = devRDCLR then
                    rdOP      <= '1';
                    datafOP   <= '1';
                    lxdarOP   <= '1';
                    busOP     <= busopRDIOT;
                    nextState <= stateIOT;
                else
                    nextState <= stateDone;
                end if;

            --
            -- stateIOT:
            -- The previous state performed a Read Data Cycle.  OR the IOT data
            -- that was read with AC.
            --

            when stateIOT =>
                acOP      <= acopORMD;
                nextState <= stateDone;

            --
            -- Operate Group1 Sequence 3 State
            --

            when stateOprGroup1Seq3 =>

                --
                -- OP 7001: IAC - Increment accumulator.
                -- The contents of the AC is incremented by 1.
                -- Carry out complements the LINK.
                --

                if IR(11) = '1' then
                    acOP <= acopIAC;
                end if;

                --
                -- Determine the next state
                --

                if IR(8) = '1' or IR(9) = '1' or IR(10) = '1' then
                    nextState <= stateOprGroup1Seq4;
                else
                    nextState <= stateDone;
                end if;

            --
            -- Operate Group1 Sequence 4 State
            --

            when stateOprGroup1Seq4 =>

                case IR(8 to 10) is

                    --
                    -- OP 7000: NOP
                    --

                    when "000" =>
                        null;

                    --
                    -- OP 7002: BSW - Byte swap
                    --

                    when "001" =>

                        --
                        -- PDP-8/E and later
                        -- OP 7002: BSW - Byte swap
                        -- AC<O-5> are exchanged with AC<6-11> respectively.
                        -- The LINK is not changed.
                        --

                        if ((swCPU = swPDP8E) or
                            (swCPU = swPDP8F) or
                            (swCPU = swPDP8A) or
                            (swCPU = swHD6120)) then
                            acOP <= acopBSW;

                        --
                        -- Pre PDP8/E
                        -- OP 7002: Equivalent to a NOP
                        --

                        else
                            null;

                        end if;

                    --
                    -- OP 7004: RAL - Rotate accumulator left.
                    -- The contents of the AC and LINK are rotated one
                    -- binary position to the left. AC(O) is shifted to
                    -- LINK and LINK is shifted to AC(11).
                    --
                    -- RAL combined with IAC only works on PDP8I and later
                    -- RAL combined with CMA is broke on on PDP8S
                    --

                    when "010" =>
                        if ((swCPU = swPDP8  and IR(11) = '1') or
                            (swCPU = swPDP8S and IR(11) = '1')) then
                            -- What should this do?
                            acOP <= acopNOP;
                        elsif swCPU = swPDP8S and IR(6) = '1' then
                            -- What should this do?
                            acOP <= acopNOP;
                        else
                            acOP <= acopRAL;
                        end if;

                    --
                    -- OP 7006: RTL - Rotate two left.
                    -- Equivalent to two RAL's.
                    --
                    -- RTL combined with IAC only works on PDP8I and later
                    -- RTL combined with CMA is broke on on PDP8S
                    --

                    when "011" =>
                        if ((swCPU = swPDP8  and IR(11) = '1') or
                            (swCPU = swPDP8S and IR(11) = '1')) then
                            -- What should this do?
                            acOP <= acopNOP;
                        elsif swCPU = swPDP8S and IR(6) = '1' then
                            -- What should this do?
                            acOP <= acopNOP;
                        else
                            acOP <= acopRTL;
                        end if;

                    --
                    -- OP 7010: RAR - Rotate accumulator right.
                    -- The contents of the AC and LINK are rotated one
                    -- binary position to the right.  AC(11) is shifted
                    -- into the LINK, and LINK is shifted to AC(O).
                    --
                    -- RAR combined with IAC only works on PDP8I and later
                    -- RAR combined with CMA is broke on on PDP8S
                    --

                    when "100" =>
                        if ((swCPU = swPDP8  and IR(11) = '1') or
                            (swCPU = swPDP8S and IR(11) = '1')) then
                            -- What should this do?
                            acOP <= acopNOP;
                        elsif swCPU = swPDP8S and IR(6) = '1' then
                            -- What should this do?
                            acOP <= acopNOP;
                        else
                            acOP <= acopRAR;
                        end if;

                    --
                    -- OP 7012: RTR - Rotate two right.
                    -- Equivalent to two RAR's.
                    --
                    -- RTR combined with IAC only works on PDP8I and later
                    -- RTR combined with CMA is broke on on PDP8S
                    --

                    when "101" =>
                        if ((swCPU = swPDP8  and IR(11) = '1') or
                            (swCPU = swPDP8S and IR(11) = '1')) then
                            -- What should this do?
                            acOP <= acopNOP;
                        elsif swCPU = swPDP8S and IR(6) = '1' then
                            -- What should this do?
                            acOP <= acopNOP;
                        else
                            acOP <= acopRTR;
                        end if;

                    --
                    -- OP 7014: RAL RAR: This instruction did a lot
                    -- of different things...
                    --
                    -- HD6120: R3L - Rotate 3 Left
                    -- HD6100: NOP
                    -- PDP8/A: Load AC with the next address (PC)
                    -- PDP8/E: ANDs AC with OPCODE
                    -- PDP8/I: What should this do?
                    -- PDP8/S: What should this do?
                    -- PDP8/L: What should this do?
                    -- PDP8:   What should this do?
                    --

                    when "110" =>
                        case swCPU is
                            when swHD6120 =>
                                acOP <= acopR3L;
                            when swHD6100 =>
                                acOP <= acopNOP;
                            when swPDP8A =>
                                acOP <= acopPC;
                            when swPDP8E =>
                                acOP <= acopUNDEF1;
                            when swPDP8I =>
                                acOP <= acopNOP;
                            when swPDP8S =>
                                acOP <= acopNOP;
                            when swPDP8L =>
                                acOP <= acopNOP;
                            when swPDP8 =>
                                acOP <= acopNOP;
                            when others =>
                                acOP <= acopNOP;
                        end case;

                    --
                    -- OP 7016: RTL RTR: This instruction did a lot
                    -- of different things...
                    --
                    -- HD6120: NOP
                    -- HD6100: NOP
                    -- PDP8/A: Load AC with the next address (PC)
                    -- PDP8/E: Load AC with 5 MSB of addr and 7 LSB of opcode
                    -- PDP8/I: What should this do?
                    -- PDP8/S: What should this do?
                    -- PDP8/L: What should this do?
                    -- PDP8:   What should this do?
                    --

                    when "111" =>
                        case swCPU is
                            when swHD6120 =>
                                acOP <= acopNOP;
                            when swHD6100 =>
                                acOP <= acopNOP;
                            when swPDP8A =>
                                acOP <= acopPC;
                            when swPDP8E =>
                                acOP <= acopUNDEF2;
                            when swPDP8I =>
                                acOP <= acopNOP;
                            when swPDP8S =>
                                acOP <= acopNOP;
                            when swPDP8L =>
                                acOP <= acopNOP;
                            when swPDP8 =>
                                acOP <= acopNOP;
                            when others =>
                                acOP <= acopNOP;
                        end case;

                    --
                    -- Everything else
                    --

                    when others =>
                        null;

                end case;
                nextState <= stateDone;

            --
            -- Operate Group 2 Sequence 2 State
            --

            when stateOprGroup2Seq2 =>

                --
                -- In USER mode, the OSR and HLT instructions are privledged
                -- and generate a User Mode interrupt.
                --

                if ((UF = '1' and IR( 9) = '1') or
                    (UF = '1' and IR(10) = '1')) then
                    if IR(4) = '1' then
                        acOP <= acopCLA;
                    end if;
                    usrtrpOP  <= usrtrpopSET;

                else

                    --
                    -- OP 7402: HLT - HALT
                    -- OP 7406: OSR HLT - HALT
                    -- OP 7606: CLA OSR HLT, LAS HLT - HALT
                    -- The HALT Operation is not particularly sequence
                    -- sensitive so it is decoded here.  The CPU will halt at
                    -- the end of the current instruction.
                    --

                    if IR(10) = '1' then
                        hlttrpOP <= hlttrpopSET;
                    end if;

                    if IR(9) = '1' then

                        --
                        -- OP 7604: LAS : Load AC with Switches.
                        --

                        if IR(4) = '1' then
                            acOP <= acopLAS;

                        --
                        -- OP 7404: OSR : OR Switch Register with accumulator.
                        --

                        else
                            acOP <= acopOSR;

                        end if;

                    else

                        --
                        -- OP 7600: CLA - Clear Accumulator
                        --

                        if IR(4) = '1' then
                            acOP <= acopCLA;

                        end if;

                    end if;

                end if;
                nextState <= stateDone;

            --
            -- Operate Group 3 Sequence 3 Mode A State
            --

            when stateOprGroup3Seq3 =>

                --
                --                    Group 3 Mode A
                --
                --  |           |           |           |           |
                --  |---|---|---|---|---|---|---|---|---|---|---|---|
                --  | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10| 11|
                --  | 1 | 1 | 1 | 1 |CLA|MQA|SCA|MQL|   |   |   | 1 |
                --  |---|---|---|---|---|---|---|---|---|---|---|---|
                --                    |   |       | |           |
                --      Sequence:     1   2       2  \____3____/
                --                                        V
                --                              0 = NOP       4 = NMI
                --                              1 = SCL       5 = SHL
                --                              2 = MUY       6 = ASR
                --                              3 = DVI       7 = LSR
                --
                --
                --                    Group 3 Mode B
                --
                --  |           |           |           |           |
                --  |---|---|---|---|---|---|---|---|---|---|---|---|
                --  | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10| 11|
                --  | 1 | 1 | 1 | 1 |CLA|MQA|   |MQL|   |   |   | 1 |
                --  |---|---|---|---|---|---|---|---|---|---|---|---|
                --                    |   | |     |             |
                --      Sequence:     1   2  \    2            /
                --                            \_______3_______/
                --                                    V
                --                          0 = NOP       10 = SCA
                --                          1 = ACS       11 = DAD
                --                          2 = MUY       12 = DST
                --                          3 = DVI       13 = SWBA
                --                          4 = NMI       14 = DPSZ
                --                          5 = SHL       15 = DPIC (MQL & MQA set)
                --                          6 = ASR       16 = DCM  (MQL & MQA set)
                --                          7 = LSR       17 = SAM
                --

                if IR = o"7431" then

                    --
                    -- OP 7431: SWAB - Switch from A to B.  The SWAB
                    -- instruction cannot be microprogrammed with any of the
                    -- Mode 3A or Mode 3B instructions.
                    --
                    -- EAE Mode B was only available on PDP8/E, PDP8/F, PDP8/M,
                    -- PDP8/A with EAE.
                    --

                    if ((swCPU = swPDP8E) or
                        (swCPU = swPDP8F) or
                        (swCPU = swPDP8M) or
                        (swCPU = swPDP8A)) then
                        emodeOP   <= emodeopSET;
                        nextState <= stateDone;
                    end if;

                elsif IR = o"7447" then

                    --
                    -- SWBA - Switch from B to A.   Clear GTF.  The SWBA
                    -- instruction cannot be microprogrammed with any of the
                    -- Mode 3A or Mode 3B instructions.
                    --

                    emodeOP   <= emodeopCLR;
                    gtfOP     <= gtfopCLR;
                    nextState <= stateDone;

                else

                    --
                    -- EAE Mode A Operations clear GTF
                    --

                    if EMODE = '0' then
                        gtfOP <= gtfopCLR;
                    end if;

                    --
                    -- All the Mode 3A and Mode 3B instructions
                    --

                    EAEIR := IR(6) & IR(8) & IR(9) & IR(10);
                    case EAEIR is

                        --
                        -- OP 7401: NOP
                        --

                        when opEAENOP =>
                            nextState <= stateDone;

                        --
                        -- OP 7403: MODEA: SCL
                        --          MODEB: ACS
                        --

                        when "0001" =>

                            if EMODE = '0' then

                                --
                                -- SCL - Step Counter Load from Memory.  The SCL
                                -- instruction is a two-word instruction.  The
                                -- value to load is contained in the operand
                                -- which is located at the next memory
                                -- location. Begin the fetch of the operand.
                                --

                                maOP      <= maopPC;
                                pcOP      <= pcopINC;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateEAEfetchAddr;

                            else

                                --
                                -- ACS - Accumulator to Step Count.
                                -- AC(7 to 11) are loaded into the Step Counter
                                -- then the AC is cleared.
                                --

                                scOP      <= scopAC7to11;
                                acOP      <= acopCLA;
                                nextState <= stateDone;

                            end if;

                        --
                        -- OP 7405: MUY - Multiply.  The Multiply instruction
                        -- is a two-word instruction.  The second word is
                        -- either the multiplier or the address of the multiplier
                        -- depending on the mode.  Begin the fetch of the operand.
                        --

                        when opEAEMUY =>
                            maOP      <= maopPC;
                            pcOP      <= pcopINC;
                            xmaOP     <= xmaopIF;
                            memselOP  <= '1';
                            busOP     <= busopRDIFaddr;
                            nextState <= stateEAEfetchAddr;

                        --
                        -- OP 7407: DVI - Divide.  The Divide instruction
                        -- is a two-word instruction.  The second word is
                        -- either the divisor or the address of the divisor
                        -- depending on the mode.  Begin the fetch of the operand.
                        --

                        when opEAEDVI =>
                            maOP      <= maopPC;
                            pcOP      <= pcopINC;
                            xmaOP     <= xmaopIF;
                            memselOP  <= '1';
                            busOP     <= busopRDIFaddr;
                            nextState <= stateEAEfetchAddr;

                        --
                        -- OP 7411: NMI
                        -- The Step Counter is initially cleared.
                        --

                        when opEAENMI =>
                            scOP      <= scopCLR;
                            nextState <= stateEAEnmi;

                        --
                        -- OP 7413: SHL - Shift Left.  The shift left
                        -- instruction is a two-word instruction. The number of
                        -- shifts is contained in operand which is located at
                        -- the next memory location.  Begin the fetch of the operand.
                        --

                        when opEAESHL =>
                            maOP      <= maopPC;
                            xmaOP     <= xmaopIF;
                            pcOP      <= pcopINC;
                            memselOP  <= '1';
                            xmaOP     <= xmaopIF;
                            busOP     <= busopRDIFaddr;
                            nextState <= stateEAEfetchAddr;

                        --
                        -- OP 7415: ASR - Arithmetic Shift Right.
                        -- The number of shifts is contained in operand which
                        -- is contained in the next memory location.  Begin the
                        -- fetch of the operand.
                        --

                        when opEAEASR =>
                            maOP      <= maopPC;
                            xmaOP     <= xmaopIF;
                            pcOP      <= pcopINC;
                            memselOP  <= '1';
                            busOP     <= busopRDIFaddr;
                            nextState <= stateEAEfetchAddr;

                        --
                        -- OP 7417: LSR - Logical Shift Right
                        -- The number of shifts is contained in operand which
                        -- is located at the next memory location.  Begin the
                        -- fetch of the operand.
                        --

                        when opEAELSR =>
                            maOP      <= maopPC;
                            xmaOP     <= xmaopIF;
                            pcOP      <= pcopINC;
                            memselOP  <= '1';
                            busOP     <= busopRDIFaddr;
                            nextState <= stateEAEfetchAddr;

                        --
                        -- OP 7441: SCA - Step Count OR with AC
                        --

                        when opEAESCA =>
                            acop      <= acopSCA;
                            nextState <= stateDone;

                        --
                        -- OP 7443: MODEA SCA/SCL
                        --          MODEB DAD
                        --

                        when opEAEDAD =>

                            if EMODE = '0' then

                                --
                                -- SCA/SCL - Step Counter Load from Memory.  The SCL
                                -- instruction is a two-word instruction.  The
                                -- value to load is contained in the operand
                                -- which is located at the next memory
                                -- location.  Begin the fetch of the operand.
                                --

                                acop      <= acopSCA;
                                pcOP      <= pcopINC;
                                maOP      <= maopPC;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateEAEfetchAddr;

                            else

                                --
                                -- DAD - Double Precision Add.  The DAD
                                -- instruction is a three-word instruction. The
                                -- second word is the first operand which is
                                -- the address of the LSW of the addend.  Begin
                                -- the fetch of the first operand.
                                --

                                pcOP      <= pcopINC;
                                maOP      <= maopPC;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateEAEfetchAddr;

                            end if;

                        --
                        -- OP 7445: MODEA: SCA/MUY
                        --          MODEB: DST

                        when opEAEDST =>

                            if EMODE = '0' then

                                --
                                -- SCA/MUY - Multiply.  The Multiply instruction
                                -- is a two-word instruction.  The second word is
                                -- either the multiplier or the address of the multiplier
                                -- depending on the mode.  Begin the fetch of the operand.
                                --

                                acop      <= acopSCA;
                                pcOP      <= pcopINC;
                                maOP      <= maopPC;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateEAEfetchAddr;

                            else

                                --
                                -- DST - Double Precision Store.
                                --

                                pcOP      <= pcopINC;
                                maOP      <= maopPC;
                                xmaOP     <= xmaopIF;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateEAEfetchAddr;

                            end if;

                        --
                        -- OP 7451: MODEA: SCA/NMI
                        --          MODEB: DPSZ
                        --

                        when opEAEDPSZ =>

                            if EMODE = '0' then

                                --
                                -- SCA/NMI -
                                -- The Step Counter is initially cleared.
                                --

                                acop      <= acopSCA;
                                scOP      <= scopCLR;
                                nextState <= stateDone;

                            else

                                --
                                -- DPSZ - Double Precision Skip if Zero
                                --

                                if AC = o"0000" and MQ = o"0000" then
                                    pcop  <= pcopINC;
                                end if;
                                nextState <= stateDone;

                            end if;

                        --
                        -- OP 7453: MODEA: SCA/SHL
                        --          MODEB: DPIC
                        --

                        when opEAEDPIC =>

                            if EMODE = '0' then

                                --
                                -- SCA/SHL - SCA combined with SHL
                                --

                                acOP      <= acopSCA;
                                maOP      <= maopPC;
                                xmaOP     <= xmaopIF;
                                pcOP      <= pcopINC;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateEAEfetchAddr;

                            else

                                --
                                -- DPIC - Double Precision Increment
                                -- Note: AC and MQ were previously swapped because
                                -- this instruction must be micro-coded with MQL and MQA.
                                --

                                if AC = o"7777" then
                                    mqOP <= mqopCLR;
                                    if MQ = o"7777" then
                                       acOP <= acopCLACLLCML;
                                    else
                                       acOP <= acopMQP1;
                                    end if;
                                else
                                    mqOP <= mqopACP1;
                                    acOP <= acopZMQ;
                                end if;
                                nextState <= stateDone;

                            end if;

                        --
                        -- OP 7455: MODEA: SCA/ASR
                        --          MODEB: DCM
                        --

                        when opEAEDCM =>

                            if EMODE = '0' then

                                --
                                -- SCA/ASR - SCA combined with ASR
                                --

                                maOP      <= maopPC;
                                xmaOP     <= xmaopIF;
                                acOP      <= acopSCA;
                                pcOP      <= pcopINC;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateEAEfetchAddr;

                            else

                                --
                                -- DCM - Double Precision Complement.
                                -- The 24-bit number in AC and MQ is complemented and
                                -- incremented. This has the effect of two complementing
                                -- the 24-bit number.  The high-order carry is propigated
                                -- into the link register.
                                -- Note: AC and MQ were previously swapped because
                                -- this instruction must be micro-coded with MQL and MQA.
                                --

                                if AC = o"0000" then
                                    mqOP <= mqopCLR;
                                    if MQ = o"0000" then
                                        acOP <= acopCLACLLCML;
                                    else
                                        acOP <= acopNEGMQ;
                                    end if;
                                else
                                    mqOP <= mqopNEGAC;
                                    acOP <= acopNOTMQ;
                                end if;
                                nextState <= stateDone;

                            end if;

                        --
                        -- OP 7457: MODEA: SCA/LSR
                        --          MODEB: SAM
                        --

                        when opEAESAM =>

                            if EMODE = '0' then

                                --
                                -- SCA/LSR - SCA combined with LSR
                                --

                                maOP      <= maopPC;
                                xmaOP     <= xmaopIF;
                                pcOP      <= pcopINC;
                                acOP      <= acopSCA;
                                memselOP  <= '1';
                                busOP     <= busopRDIFaddr;
                                nextState <= stateEAEfetchAddr;

                            else

                                --
                                -- SAM - Subtract AC from MQ.
                                -- GTF is set if signed MQ >= signed AC
                                -- otherwise GTF is cleared.
                                --

                                acOP  <= acopMQSUB;
                                if signed(MQ) >= signed(AC) then
                                    gtfOP <= gtfopSET;
                                else
                                    gtfOP <= gtfopCLR;
                                end if;
                                nextState <= stateDone;

                            end if;

                        --
                        -- Everything else
                        --

                        when others =>
                            assert false report "stateOprGroup3Seq3: Undecoded instruction" severity warning;
                            nextState <= stateDone;

                    end case;

                end if;

            --
            -- This state performs a read address cycle.
            -- The next state will do a read data bus.
            --

            when stateMRIreadAddr =>
                rdOP     <= '1';
                xmaOP    <= xmaopIF;
                memselOP <= '1';
                busOP    <= busopRDIFaddr;
                if ((IR(3 to 4) = amDZ) or IR(3 to 4) = amDC) then
                    nextState <= stateMRIexecute;
                else
                    nextState <= stateMRIreadDataIND;
                end if;

            --
            -- This state perfored a read data bus cycle.
            -- The data that was read is in MD.
            --

            when stateMRIreadDataIND =>

                if MA(0 to 8) = maAutoIncr then

                    --
                    -- Writeback auto incremented data.
                    --  MB <- MD + 1
                    --  MEM[IF'MA] <- MB
                    --

                    wrOP      <= '1';
                    mbOP      <= mbopMDP1;
                    xmaOP     <= xmaopIF;
                    memselOP  <= '1';
                    busOP     <= busopWRIF;
                    nextState <= stateMRIreadINCaddr;

                else

                    --
                    -- Non-autoincrement addresses
                    -- Start address phase of indirect data read
                    -- Address input is in MD
                    --

                    case IR(0 to 2) is

                        --
                        -- MA <- MD
                        -- MD <- MEM[IB'MA]
                        --

                        when opJMS | opJMP =>
                            maOP      <= maopMD;
                            xmaOP     <= xmaopIB;
                            memselOP  <= '1';
                            busOP     <= busopRDIBaddr;
                            nextState <= stateMRIexecute;

                            --
                            -- MA <- MB
                            -- MD <- MEM[DF'MA]
                            --

                        when others =>
                            maOP      <= maopMD;
                            xmaOP     <= xmaopDF;
                            datafOP   <= '1';
                            memselOP  <= '1';
                            busOP     <= busopRDDFaddr;
                            nextState <= stateMRIreadINDdata;
                    end case;

                end if;

            --
            -- Start address phase of indirect data read
            -- Address input is in MB
            --

            when stateMRIreadINCaddr =>
                case IR(0 to 2) is

                    --
                    -- MA <- MB
                    -- MD <- MEM[IB'MA]
                    --

                    when opJMS | opJMP =>
                        maOP      <= maopMB;
                        xmaOP     <= xmaopIB;
                        memselOP  <= '1';
                        busOP     <= busopRDIBaddr;
                        nextState <= stateMRIexecute;

                    --
                    -- MA <- MB
                    -- MD <- MEM[DF'MA]
                    --

                    when others =>
                        maOP      <= maopMB;
                        xmaOP     <= xmaopDF;
                        datafOP   <= '1';
                        memselOP  <= '1';
                        busOP     <= busopRDDFaddr;
                        nextState <= stateMRIreadINDdata;
                end case;

            --
            -- Start data phase of indirect data read
            --  MD <- MEM[DF'MA]
            --

            when stateMRIreadINDdata =>
                rdOP      <= '1';
                xmaOP     <= xmaopDF;
                datafOP   <= '1';
                memselOP  <= '1';
                busOP     <= busopRDDFdata;
                nextState <= stateMRIexecute;

            --
            -- Dispatch the MRI ops.   The previous state was a read data cycle.
            --  The data is in MD and the address is MA.
            --

            when stateMRIexecute =>
                case IR(0 to 2) is

                    --
                    --  AC <- AC and MD
                    --

                    when opAND =>
                        acOP      <= acopANDMD;
                        nextState <= stateDone;

                    --
                    -- AC <- AC + MD
                    --

                    when opTAD =>
                        acOP      <= acopADDMD;
                        nextState <= stateDone;

                    --
                    -- MB <- MD + 1
                    -- IF MD = 7777 (or MB = 0000) Then
                    --    PC <- PC + 1;
                    -- ENDIF
                    -- IF ISZ DIRECT THEN
                    --    MEM[IF'MA] <- MB
                    -- ELSE
                    --    MEM[DF'MA] <- MB
                    -- ENDIF
                    -- Note: Checking MD against 7777 saves a state...
                    --

                    when opISZ =>
                        mbOP <= mbopMDP1;
                        if MD = o"7777" then
                            pcOP <= pcopINC;
                        end if;
                        if ((IR(3 to 4) = amDZ) or IR(3 to 4) = amDC) then
                            wrOP     <= '1';
                            xmaOP    <= xmaopIF;
                            memselOP <= '1';
                            busOP    <= busopWRIF;
                        else
                            wrOP     <= '1';
                            xmaOP    <= xmaopDF;
                            datafOP  <= '1';
                            memselOP <= '1';
                            busOP    <= busopWRDF;
                        end if;
                        nextState <= stateDone;

                    --
                    -- MB <- AC
                    -- AC <- 0000
                    -- IF DCA DIRECT THEN
                    --    MEM[IF'MA] <- MB
                    -- ELSE
                    --    MEM[DF'MA] <- MB
                    -- ENDIF
                    --

                    when opDCA =>
                        mbOP <= mbopAC;
                        acOP <= acopCLA;
                        if ((IR(3 to 4) = amDZ) or IR(3 to 4) = amDC) then
                            wrOP     <= '1';
                            xmaOP    <= xmaopIF;
                            memselOP <= '1';
                            busOP    <= busopWRIF;
                        else
                            wrOP     <= '1';
                            xmaOP    <= xmaopDF;
                            datafOP  <= '1';
                            memselOP <= '1';
                            busOP    <= busopWRDF;
                        end if;
                        nextState <= stateDone;

                    --
                    -- opJMS
                    --
                    -- When the PEX Flip-flop is set, the CPU shall exit from
                    -- Panel Mode to Main Memory (i.e., clear CTRLFF) during
                    -- the next JMP, JMS, RTN1 or RTN2 instruction.  PEX is
                    -- cleared by the JMP, JMS, RTN1 or RTN instruction.
                    --
                    -- IF <- IB
                    -- UF <- UB
                    -- IIFF <- '0'
                    -- MB <- PC
                    -- MEM[IB'MA] <- MB
                    -- IF PEX = '1' THEN
                    --    CTRLFF <- '0'
                    --    PEX    <- '0'
                    -- ENDIF
                    --

                    when opJMS =>
                        ifOP     <= ifopIB;
                        ufOP     <= ufopUB;
                        wrOP     <= '1';
                        mbOP     <= mbopPC;
                        pcOP     <= pcopMAP1;
                        xmaOP    <= xmaopIB;
                        memselOP <= '1';
                        busOP    <= busopWRIB;
                        if PEX = '1' then
                            ctrlffOP <= ctrlffopCLR;
                            pexOP    <= pexopCLR;
                        end if;
                        nextState <= stateDone;

                    --
                    -- opJMP
                    --
                    -- When the PEX Flip-flop is set, the CPU shall exit from
                    -- Panel Mode to Main Memory (i.e., clear CTRLFF) during
                    -- the next JMP, JMS, RTN1 or RTN2 instruction.  PEX is
                    -- cleared by the JMP, JMS, RTN1 or RTN instruction.
                    --
                    -- IF <- IB
                    -- UF <- UB
                    -- PC <- MA
                    -- IF PEX = '1' THEN
                    --    CTRLFF <- '0'
                    --    PEX    <- '0'
                    -- ENDIF
                    --

                    when opJMP =>
                        ifOP <= ifopIB;
                        ufOP <= ufopUB;
                        pcOP <= pcopMA;
                        if PEX = '1' then
                            ctrlffOP <= ctrlffopCLR;
                            pexOP    <= pexopCLR;
                        end if;
                        nextState <= stateDone;

                    --
                    -- Can't get to any of these
                    --

                    when opIOT =>
                        assert false report "stateMRIexecute: IOT direct." severity warning;
                        nextState <= stateDone;
                    when opOPR =>
                        assert false report "stateMRIexecute: OPR direct." severity warning;
                        nextState <= stateDone;
                    when others =>
                        assert false report "stateMRIexecute: Others direct." severity warning;
                        nextState <= stateDone;
                end case;

            --
            -- The previous state set the MA register
            -- This state handles the address phase of the read cycle.
            --  MD <- MEM[IF,MA]
            --

            when stateEAEfetchAddr =>
                rdOP      <= '1';
                memselOP  <= '1';
                busOP     <= busopRDIFdata;
                nextState <= stateEAEfetchData;

            --
            -- This is the data phase of the EAE second word read.
            -- At the end of this cycle, the second word is in the MD register.
            --  MD <- MEM[IF,MA]
            --
            -- This state will re-dispatch EAE ops that have a single operand
            -- that is used as 'immediate data'.  This state will begin the
            -- fetch of indirect data for EAE ops with indirect operands.
            --

            when stateEAEfetchData =>

                EAEIR := IR(6) & IR(8) & IR(9) & IR(10);
                case EAEIR is

                    --
                    -- OP 7401: NOP
                    --

                    when opEAENOP =>
                        nextState <= stateDone;

                    --
                    -- OP 7403: MODEA: SCL
                    --          MODEB: ACS
                    --

                    when opEAEACS =>

                        if EMODE = '0' then

                            --
                            -- SCL - The ones complement of the last five bits
                            -- of this operand are loaded into the Step Counter
                            -- and the program resumes at the instruction word
                            -- following the operand.
                            --

                            scOP      <= scopNOTMD7to11;
                            nextState <= stateDone;

                        else

                            --
                            -- ACS - Accumulator to Step Count.
                            -- The ACS instruction doesn't re-dispatch here.
                            -- You shouldn't get here.
                            --

                            assert false report "stateEAEfetchData: ACS should not re-dispatch here" severity warning;
                            nextState <= stateLALA;

                        end if;

                    --
                    -- OP 7405: MUY - Multiply.
                    -- In MODEA, the operand is the multiplier.
                    -- In MODEB, the operand is the address of the multipler,
                    -- which is possibly pre-incremented before use.  Start the
                    -- multiply operation.
                    --

                    when opEAEMUY =>
                        if EMODE = '0' then

                            EAEop     <= eaeopMUY;
                            nextState <= stateEAEmuy;

                        else

                            if MA(3 to 11) = maAutoIncr then

                                --
                                -- Start the writeback of the incremented data
                                --

                                wrOP      <= '1';
                                mbOP      <= mbopMDP1;
                                --XMAOPTBD
                                datafOP   <= '1';
                                memselOP  <= '1';
                                nextState <= stateEAEindWrite;

                            else

                                --
                                -- Start address phase of indirect data read
                                --

                                maOP      <= maopMD;
                                --XMAOPTBD
                                datafOP   <= '1';
                                memselOP  <= '1';
                                nextState <= stateEAEindReadAddr;

                            end if;
                        end if;

                    --
                    -- OP 7407: DVI - Divide
                    -- In MODEA, the operand is the divisor
                    -- In MODEB, the operand is the address of the divisor
                    -- which is possibly pre-incremented before use.  The
                    -- divisor is in MD.
                    --

                    when opEAEDVI =>
                        if EMODE = '0' then

                            --
                            -- Handle divide overflow condition
                            --

                            if AC >= MD then
                                scOP      <= scopCLR;
                                acOP      <= acopCLLCML;
                                mqOP      <= mqopSHL1;
                                nextState <= stateDone;

                            --
                            -- Handle normal divide condition
                            --

                            else
                                mqaOP     <= mqaopMQ;
                                scOP      <= scopCLR;
                                acOP      <= acopCLL;
                                nextState <= stateEAEsubDVI;

                            end if;

                        else
                            if MA(3 to 11) = maAutoIncr then

                                --
                                -- Start the writeback of the incremented data
                                --

                                wrOP      <= '1';
                                mbOP      <= mbopMDP1;
                                --XMAOPTBD
                                --DATAFOP OR IFETCHOP
                                memselOP  <= '1';
                                nextState <= stateEAEindWrite;

                            else

                                --
                                -- Start address phase of indirect data read
                                --

                                maOP      <= maopMD;
                                --XMAOPTBD
                                datafOP   <= '1';
                                memselOP  <= '1';
                                nextState <= stateEAEindReadAddr;

                            end if;
                        end if;

                    --
                    -- OP 7411: NMI - Normalize
                    -- The NMI instruction doesn't re-dispatch here.
                    -- You shouldn't get here.
                    --

                    when opEAENMI =>
                        assert false report "stateEAEfetchData: NMI should not re-dispatch here" severity warning;
                        nextState <= stateLALA;

                    --
                    -- OP 7413: SHL - Shift Left.
                    -- The second word of the two-word instruction defines the
                    -- number of shifts to be performed. In Mode A, the number
                    -- of shifts performed is equal to one more than the number
                    -- in the last five bits of the second word.  In Mode B,
                    -- the number of shifts performed is equal to the number in
                    -- the last five bits of the second word.  A shift count of
                    -- zero is legal, and leaves the link, AC, and MQ registers
                    -- unchaged.
                    --

                    when opEAESHL =>
                        if EMODE = '0' then

                            --
                            -- Mode A:
                            -- Handle case where SHL Shift count is maxed out.
                            --

                            if unsigned(MD(7 to 11)) > 24 then
                                scOP      <= scopCLR;
                                mqOP      <= mqopCLR;
                                acOP      <= acopCLACLL;
                                nextState <= stateDone;

                            --
                            -- Mode A:
                            -- Normal case where SHL shift count not maxed out.
                            --

                            else
                                scOP      <= scopMDP1;
                                nextState <= stateEAEshift;

                            end if;

                        else

                            --
                            -- Mode B:
                            -- Handle case where SHL Shift count is maxed out.
                            --

                            if unsigned(MD(7 to 11)) > 25 then
                                scOP      <= scopSET;
                                mqOP      <= mqopCLR;
                                acOP      <= acopCLACLL;
                                nextState <= stateDone;

                            --
                            -- Mode B:
                            -- Handle case where SHL Shift count is zero
                            --

                            elsif unsigned(MD(7 to 11)) = 0 then
                                scOP      <= scopSET;
                                nextState <= stateDone;

                            --
                            -- Mode B:
                            -- Normal case where SHL shift count not maxed out.
                            --

                            else
                                scOP      <= scopMD7to11;
                                nextState <= stateEAEshift;

                            end if;
                        end if;

                    --
                    -- OP 7415: ASR - Arithmetic Shift Right.
                    -- The second word of the two-word instruction defines the
                    -- number of shifts to be performed. In Mode A, the number
                    -- of shifts performed is equal to one more than the number
                    -- in the last five bits of the second word.  In Mode B,
                    -- the number of shifts performed is equal to the number in
                    -- the last five bits of the second word.  A shift count of
                    -- zero is legal, and loads the link from AC(0) but leaves
                    -- the AC and MQ registers unchaged.
                    --

                    when opEAEASR =>
                        if EMODE = '0' then

                            --
                            -- Mode A:
                            -- Handle case where ASR Shift count is maxed out.
                            -- Sign extended AC into L and MQ
                            --

                            if unsigned(MD(7 to 11)) > 23 then
                                if AC(0) = '0' then
                                    acOP <= acopCLACLL;
                                    mqOP <= mqopCLR;
                                else
                                    acOP <= acopCLACLLCMACML;
                                    mqOP <= mqopSET;
                                end if;
                                scOP      <= scopCLR;
                                nextState <= stateDone;

                            --
                            -- Mode A:
                            -- Normal case where ASR shift count not maxed out.
                            -- Sign extend AC into L
                            --

                            else

                                scOP <= scopMDP1;
                                if AC(0) = '0' then
                                    acOP  <= acopCLL;
                                else
                                    acOP  <= acopCLLCML;
                                end if;
                                nextState <= stateEAEshift;

                            end if;

                        else

                            --
                            -- Mode B:
                            -- Handle case where ASR Shift count is maxed out.
                            -- Shift sign extended AC
                            --

                            if unsigned(MD(7 to 11)) > 25 then
                                if AC(0) = '0' then
                                    acOP  <= acopCLACLL;
                                    mqOP  <= mqopCLR;
                                    gtfOP <= gtfopCLR;
                                else
                                    acOP  <= acopCLACLLCMACML;
                                    mqOP  <= mqopSET;
                                    gtfOP <= gtfopSET;
                                end if;
                                scOP      <= scopSET;
                                nextState <= stateDone;

                            --
                            -- Mode B:
                            -- Handle case where ASR Shift count is zero
                            -- Sign extend AC into L
                            --

                            elsif unsigned(MD(7 to 11)) = 0 then
                                if AC(0) = '0' then
                                    acOP  <= acopCLL;
                                else
                                    acOP  <= acopCLLCML;
                                end if;
                                nextState <= stateDone;

                            --
                            -- Mode B:
                            -- Normal case where ASR shift count not maxed out.
                            --

                            else
                                scOP      <= scopMD7to11;
                                if AC(0) = '0' then
                                    acOP  <= acopCLL;
                                else
                                    acOP  <= acopCLLCML;
                                end if;
                                nextState <= stateEAEshift;

                            end if;

                        end if;

                    --
                    -- OP 7417: LSR - Logical Shift Right
                    -- The second word of the two-word instruction defines the
                    -- number of shifts to be performed. In Mode A, the number
                    -- of shifts performed is equal to one more than the number
                    -- in the last five bits of the second word.  In Mode B,
                    -- the number of shifts performed is equal to the number in
                    -- the last five bits of the second word.  A shift count of
                    -- zero is legal, and clears the link without changing the
                    -- AC or MQ registers.
                    --

                    when opEAELSR =>
                        if EMODE = '0' then

                            --
                            -- Mode A:
                            -- Handle case where LSR Shift count is maxed out.
                            --

                            if unsigned(MD) > 23 then
                                scOP      <= scopCLR;
                                acOP      <= acopCLACLL;
                                mqOP      <= mqopCLR;
                                nextState <= stateDone;

                            --
                            -- Mode A:
                            -- Normal case where LSR shift count not maxed out.
                            --

                            else
                                scOP      <= scopMDP1;
                                acOP      <= acopCLL;
                                nextState <= stateEAEshift;

                            end if;

                        else

                            --
                            -- Mode B:
                            -- Handle case where LSR Shift count is maxed out.
                            --

                            if unsigned(MD) > 24 then
                                scOP      <= scopCLR;
                                acOP      <= acopCLACLL;
                                mqOP      <= mqopCLR;
                                gtfOP     <= gtfopCLR;
                                nextState <= stateEAEshift;

                            --
                            -- Mode B:
                            -- Handle case where LSR Shift count is zero
                            --

                            elsif unsigned(MD(7 to 11)) = 0 then
                                acOP      <= acopCLL;
                                nextState <= stateDone;

                            --
                            -- Mode B:
                            -- Normal case where LSR shift count not maxed out.
                            --

                            else
                                scOP      <= scopMD7to11;
                                acOP      <= acopCLL;
                                nextState <= stateEAEshift;

                            end if;
                        end if;

                    --
                    -- OP 7441: SCA - Step Count OR with AC
                    --
                    -- The ones complement of the last five bits of this
                    -- operand are loaded into the Step Counter and the
                    -- program resumes at the instruction word following
                    -- the operand.
                    --

                    when opEAESCA =>
                        assert false report "stateEAEfetchData: SCA should not re-dispatch here" severity warning;
                        nextState <= stateLALA;

                    --
                    -- OP 7407: DAD - Double Precision Add.  DAD is MODEB only.
                    -- In MODEB, the operand is the address of the quotient,
                    -- which is possibly pre-incremented before use.
                    --

                    when opEAEDAD =>
                        if EMODE = '0' then
                            assert false report "stateEAEfetchData: SCA/SCL should not re-dispath here" severity warning;
                            nextState <= stateLALA;
                        else
                            if MA(3 to 11) = maAutoIncr then

                                --
                                -- Start the writeback of the incremented data
                                --

                                wrOP      <= '1';
                                mbOP      <= mbopMDP1;
                                --XMAOPTBD
                                --DATAFOP OR IFETCHOP
                                memselOP  <= '1';
                                nextState <= stateEAEindWrite;

                           else

                                --
                                -- Start address phase of indirect data
                                --

                                maOP      <= maopMD;
                               --XMAOPTBD
                                datafOP   <= '1';
                                memselOP  <= '1';
                                nextState <= stateEAEindReadAddr;

                            end if;
                        end if;

                    --
                    -- OP 7445: SCA/MUY -
                    --          DST - Double Precision Store.
                    --

                    when opEAEDST =>
                        if EMODE = '0' then
                            EAEop     <= eaeopMUY;
                            nextState <= stateEAEmuy;
                        else
                            if MA(3 to 11) = maAutoIncr then

                                --
                                -- Start the writeback of the incremented data
                                --

                                wrOP      <= '1';
                                mbOP      <= mbopMDP1;
                                --XMAOPTBD
                                --DATAFOP OR IFETCHOP
                                memselOP  <= '1';
                                nextState <= stateEAEindWrite;

                           else

                                --
                                -- Start address phase of indirect data
                                --

                                maOP      <= maopMD;
                                xmaOP     <= xmaopDF;
                                datafOP   <= '1';
                                memselOP  <= '1';
                                nextState <= stateEAEindReadAddr;

                            end if;
                        end if;

                    --
                    -- OP 7451:  DPSZ - Double Precision Skip if Zero
                    --

                    when opEAEDPSZ =>
                        assert false report "stateEAEfetchData: DPSZ should not re-dispatch here" severity warning;
                        nextState <= stateLALA;

                    --
                    -- OP 7453: DPIC - Double Precision Increment
                    --

                    when opEAEDPIC =>
                        assert false report "stateEAEfetchData: DPIC should not re-dispatch here" severity warning;
                        nextState <= stateLALA;

                    --
                    -- OP 7455: DCM - Double Precision Complement.
                    --

                    when opEAEDCM =>
                        assert false report "stateEAEfetchData: DCM should not re-dispatch here" severity warning;
                        nextState <= stateLALA;

                    --
                    -- OP 7457: SAM - Subtract AC from MQ.
                    --

                    when opEAESAM =>
                        assert false report "stateEAEfetchData: SAM should not re-dispatch here" severity warning;
                        nextState <= stateLALA;

                    --
                    -- Everything else.
                    --

                    when others =>
                        assert false report "stateEAEfetchData: Unimplemented EAE case" severity warning;
                        nextState <= stateDone;
                end case;

            --
            -- statePOPaddr
            -- This state increments the stack pointer SP1 or SP2, sets
            -- the MA to the incremented value, and performs a Read Addr cycle.
            --   MD <- MEM[000'MA]

            when statePOPaddr =>
                rdOP      <= '1';
                acOP      <= acopCLA;
                xmaOP     <= xmaopCLR;
                memselOP  <= '1';
                busOP     <= busopRDZFdata;
                nextState <= statePOPdata;

            --
            -- statePOPdata
            -- This state completed the read of the top-of-stack and
            -- placed the data in the MD.  It also cleared AC so that
            -- we can add MD to the AC.
            --   AC <- MD
            --

            when statePOPdata =>
                acOP      <= acopADDMD;
                nextState <= stateDone;

            --
            -- RTN1 Read State
            -- The previous state incremented SP1.
            -- This state sets up a Read Addr Cycle to the memory location
            -- pointed to by SP2.
            --
            -- If Instructions are being fetched from main memory, the stacks
            -- are located in field 0 of main memory.  If Instructions are
            -- being fetched from panel memory, the stacks are located in field
            -- 0 of panel memory, except for the case of a RTN from control
            -- panel  memory via a RTN1 or RTN2 Instruction. In this case, the
            -- main memory stack is accessed by the instruction fetched from
            -- panel memory.
            --

            when stateRTN1 =>
                maOP      <= maopSP1;
                xmaOP     <= xmaopCLR;
                memselOP  <= '1';
                busOP     <= busopRDZFaddr;
                nextState <= stateRTNaddr;

            --
            -- RTN2 Read State
            -- The previous state incremented SP2.
            -- This state sets up a Read Addr Cycle to the memory location
            -- pointed to by SP2.
            --
            -- If Instructions are being fetched from main memory, the stacks
            -- are located in field 0 of main memory.  If Instructions are
            -- being fetched from panel memory, the stacks are located in field
            -- 0 of panel memory, except for the case of a RTN from control
            -- panel  memory via a RTN1 or RTN2 Instruction. In this case, the
            -- main memory stack is accessed by the instruction fetched from
            -- panel memory.
            --

            when stateRTN2 =>
                maOP      <= maopSP2;
                xmaOP     <= xmaopCLR;
                memselOP  <= '1';
                busOP     <= busopRDZFaddr;
                nextState <= stateRTNaddr;

            --
            -- stateRTNaddr
            -- The previous state peformed a Read Addr cycle to the top-of-stack.
            -- This state sets up a Read Data Cycle.
            --
            -- If Instructions are being fetched from main memory, the stacks
            -- are located in field 0 of main memory.  If Instructions are
            -- being fetched from panel memory, the stacks are located in field
            -- 0 of panel memory, except for the case of a RTN from control
            -- panel  memory via a RTN1 or RTN2 Instruction. In this case, the
            -- main memory stack is accessed by the instruction fetched from
            -- panel memory.
            --

            when stateRTNaddr =>
                rdOP      <= '1';
                xmaOP     <= xmaopCLR;
                memselOP  <= '1';
                busOP     <= busopRDZFdata;
                nextState <= stateRTNdata;

            --
            -- stateRTNdata
            -- The previous state performed a Read Data Cycle to the
            -- top-of-stack.
            --
            -- The contents of the Instruction Buffer (IB) is loaded into the
            -- Instruction Field (IF) register.
            --
            -- If the Interrupt Inhibit Flip Flop (II) is set, then the Force
            -- Zero (FZ) flag is cleared.
            --
            -- When the PEX Flip-flop is set, the CPU shall exit from Panel
            -- Mode to Main Memory (i.e., clear CTRLFF) during the next JMP,
            -- JMS, RTN1 or RTN2 instruction.
            --
            -- PEX is cleared by the JMP, JMS, RTN1 or RTN2 instruction.
            --

            when stateRTNdata =>
                ifOP <= ifopIB;
                pcOP <= pcopMD;

                if PEX = '1' then
                    ctrlffOP <= ctrlffopCLR;
                    pexOP    <= pexopCLR;
                end if;

                if II = '1' then
                    fzOP  <= fzopCLR;
                end if;
                nextState <= stateDone;

            --
            -- stateEAEindWrite
            -- This state performs an indirect write
            --

            when stateEAEindWrite =>
                maOP      <= maopMB;
                --XMAOPTBD
                datafOP   <= '1';
                memselOP  <= '1';
                nextState <= stateEAEindReadAddr;

            --
            -- stateEAEindReadAddr -
            -- The previous state set the MA register to the indirect address.
            -- This state handles the address phase of the EAE indirect read cycle.
            --

            when stateEAEindReadAddr =>
                rdOP      <= '1';
                --XMAOPTBD
                datafOP   <= '1';
                memselOP  <= '1';
                nextState <= stateEAEindReadData;

            --
            -- stateEAEindReadData -
            -- This state handles the data phase of the EAE indirect read cycle.
            -- At the end of this state, the indirect data should be in the MD
            -- register.  This state then redispatches the MUY, DVI, DAD, and
            -- DST instructions.  At this point the operand is in the MD register.
            --

            when stateEAEindReadData =>
                EAEIR := IR(6) & IR(8) & IR(9) & IR(10);
                case EAEIR is

                    --
                    -- MUY - Setup EAE and go to next state.
                    --

                    when opEAEMUY =>
                        eaeOP     <= eaeopMUY;
                        nextState <= stateEAEmuy;

                    --
                    -- DVI - Check for overflow right away.  If overflow, then
                    -- set state and exit. Otherwise setup EAE, MQ, SC, and go to
                    -- next state.  The Divisor is in MD.
                    --

                    when opEAEDVI =>

                        --
                        -- Handle divide overflow condition
                        --

                        if AC >= MD then
                            scOP      <= scopCLR;
                            acOP      <= acopCLLCML;
                            mqOP      <= mqopSHL1;
                            nextState <= stateDone;

                        --
                        -- Handle normal divide condition
                        --

                        else
                            mqaOP     <= mqaopMQ;
                            scOP      <= scopCLR;
                            acOP      <= acopCLL;
                            nextState <= stateEAEsubDVI;

                        end if;

                    --
                    -- DAD - Add the contents of MD to MQ.
                    --
                    --

                    when opEAEDAD =>
                        maOP      <= maopINC;
                        mqOP      <= mqopADDMD;
                        --XMAOPTBD
                        datafOP   <= '1';
                        memselOP  <= '1';

                        --
                        -- Handle cases where carry does/doesnot come from MQ
                        --

                        if (unsigned('0'& MQ) + unsigned('0' & MD)) > 4095 then
                            nextState <= stateEAEreadDADaddr1;
                        else
                            nextState <= stateEAEreadDADaddr0;
                        end if;

                    --
                    -- DST - Stores the MQ data to MEM[XMA & MA]
                    --

                    when opEAEDST =>
                        wrOP      <= '1';
                        mbOP      <= mbopMQ;
                        --XMAOPTBD
                        --DATAFOP OR IFETCHOP
                        memselOP  <= '1';
                        nextState <= stateEAEdst;

                    --
                    -- Everything else.
                    --

                    when others =>
                        nextState <= stateLALA;

                end case;

            --
            -- StateEAEshift - This is where all the shift loop for the EAE ASR,
            -- LSR, and SHR instructions occurs.  On right shifts, bits shifted
            -- out of of EAE(24) are shifted into the GTF to facillitate
            -- round-off operations.  In Mode A, the  shift operations complete
            -- with SC set to zero.  In Mode B the shift operations complete
            -- with the SC set to 31.
            --

            when stateEAEshift =>
                EAEIR := IR(6) & IR(8) & IR(9) & IR(10);
                if unsigned(SC) = 0 then
                    if EAEIR = opEAELSR then
                        acOP <= acopCLL;
                    end if;
                    if EMODE = '0' then
                        scOP <= scopCLR;
                    else
                        scOP <= scopSET;
                    end if;
                    nextState <= stateDone;
                else
                    case EAEIR is
                        when opEAELSR =>
                            if EMODE = '1' then
                                if MQ(11) = '0' then
                                    gtfOP <= gtfopCLR;
                                else
                                    gtfOP <= gtfopSET;
                                end if;
                            end if;
                            acOP <= acopLSR;
                            if AC(11) = '0' then
                                mqOP <= mqopSHR0;
                            else
                                mqOP <= mqopSHR1;
                            end if;
                        when opEAEASR =>
                            if EMODE = '1' then
                                if MQ(11) = '0' then
                                    gtfOP <= gtfopCLR;
                                else
                                    gtfOP <= gtfopSET;
                                end if;
                            end if;
                            acOP <= acopASR;
                            if AC(11) = '0' then
                                mqOP <= mqopSHR0;
                            else
                                mqOP <= mqopSHR1;
                            end if;
                        when opEAESHL =>
                            mqOP <= mqopSHL0;
                            if MQ(0) = '0' then
                                acOP <= acopSHL0;
                            else
                                acOP <= acopSHL1;
                            end if;
                        when others =>
                            assert false report "stateEAEshift: Not a shift OP" severity warning;
                    end case;
                    scOP      <= scopDEC;
                    nextState <= stateEAEwait;
                end if;

            --
            -- stateEAEwait
            -- stateEAEshift has a hard time meeting timing.  This gives the
            -- accumulators a little extra time to settle.
            --

            when stateEAEwait =>
                nextState <= stateEAEshift;

            --
            -- stateEAEnmi
            -- The Step Counter is initially cleared.  The contents of the
            -- Link, AC, and MQ registers are are shifted left until AC(0) and
            -- AC(1) are different or until AC(2) through MQ(11) are all zero.
            -- The Step Count register is increment once for every shift.  If
            -- MODE B, and the contents of AC & MQ is o"4000_0000", the AC is
            -- cleared.
            --

            when stateEAEnmi =>
                if (AC(0) /= AC(1)) or (unsigned(AC(2 to 11)) = 0 and unsigned(MQ) = 0) then
                    if EMODE = '1' and unsigned(AC) = 2048 and unsigned(MQ) = 0 then
                        acOP  <= acopCLA;
                    end if;
                    nextState <= stateDone;
                else
                    scOP      <= scopINC;
                    mqOP      <= mqopSHL0;
                    if MQ(0) = '0' then
                        acOP  <= acopSHL0;
                    else
                        acOP  <= acopSHL1;
                    end if;
                    nextState <= stateEAEnmi;
                end if;

            --
            -- The contents of the MQ are multiplied by the multiplier (in the
            -- MD) and the MSBs of the 24 bit result are left in the AC and the
            -- LSBs are left in the MQ. The multiplication is unsigned.  If AC
            -- is non-zero, the product is added to AC.
            --

            when stateEAEmuy =>
                acOP      <= acopEAEZAC;
                mqOP      <= mqopEAE;
                scOP      <= scop12;
                nextState <= stateDone;

            --
            -- stateEAEsubDVI - Long division is a shift and subtract
            -- operation.  This state handles the subtraction.
            -- MQ = (AC & MQ) / MD
            -- AC = (AC & MQ) % MD
            --

            when stateEAEsubDVI =>
                if unsigned(LAC) >= unsigned(MD) then
                    mqOP  <= mqopSHL1;
                    acOP  <= acopSUBMD;
                else
                    mqOP  <= mqopSHL0;
                end if;
                scOP      <= scopINC;
                nextState <= stateEAEshiftDVI;

            --
            -- stateEAEshiftDVI - Long division is a shift and subtract
            -- operation.  This state handles the shift operation.
            --

            when stateEAEshiftDVI =>

                --
                -- Check for loop exit condtions
                --

                if unsigned(SC) = 13 then
                    acOP      <= acopCLL;
                    nextState <= stateDone;

                --
                -- Shift L, AC, and MQ left
                --

                else
                    mqaOP     <= mqaopSHL;
                    if MQA(0) = '0' then
                        acOP  <= acopSHL0;
                    else
                        acOP  <= acopSHL1;
                    end if;
                    nextState <= stateEAEsubDVI;

                end if;

            --
            -- stateEAEreadDADaddr0
            -- This is the address phase of the read cycle for the second
            -- operand (third word).  This state is for cases where there is no
            -- carry from the addition of MQ.
            --

            when stateEAEreadDADaddr0 =>
                rdOP      <= '1';
                acOP      <= acopCLL;
                --XMAOPTBD
                datafOP   <= '1';
                memselOP  <= '1';
                nextState <= stateEAEreadDADdata0;

            --
            -- stateEAEreadDADaddr1
            -- This is the address phase of the read cycle for the second
            -- operand (third word).   This state is for cases where there is a
            -- carry from the addition of MQ.  Clear the link for the add
            -- instruction in the next state.
            --

            when stateEAEreadDADaddr1 =>
                rdOP      <= '1';
                acOP      <= acopCLL;
                --XMAOPTBD
                datafOP   <= '1';
                memselOP  <= '1';
                nextState <= stateEAEreadDADdata1;

            --
            -- stateEAEreadDADdata0
            -- This is the data phase of the read cycle for the second operand
            -- (third word).  This state is for cases where there is no carry
            -- from the addition of MQ. Clear the link for the add instruction
            -- in the next state.
            --

            when stateEAEreadDADdata0 =>
                acOP      <= acopADDMD;
                nextState <= stateDone;

            --
            -- stateEAEreadDADdata1
            -- This is the data phase of the read cycle for the second operand
            -- (third word).  This state is for cases where there is a carry
            -- from the addition of MQ.
            --

            when stateEAEreadDADdata1 =>
                acOP      <= acopADDMDP1;
                nextState <= stateDone;

            --
            -- stateEAEdst - This state stores the AC data to MEM[XMA & (MA + 1)]
            --

            when stateEAEdst =>
                wrOP      <= '1';
                maOP      <= maopINC;
                mbOP      <= mbopAC;
                xmaOP     <= xmaopDF;
                memselOP  <= '1';
                datafOP   <= '1';
                nextState <= stateDone;

            --
            -- Done State
            -- This is the last state of the instruction.  This wastes a state
            -- but makes it easy to 'see' the end of the instruction cycle.
            --

            when stateDone =>
                nextstate <= stateCheckReq;

            --
            -- You've landed in LA-LA land.  You shouldn't get here.  Somehow
            -- some OPCODE was not decoded correctly or the next state for the
            -- State Machine was not set.  Plug your ears, close your eyes and
            -- scream LA-LA-LA-LA-LA-LA-LA-LA-LA-LA-LA.
            --

            when stateLALA =>
                nextState <= stateLALA;

        end case;

    end process NEXT_STATE;

    mem : block
    begin

        --!
        --! LXPAR is generated for panel memory accesses: It is asserted when:
        --! #.  MEMSEL asserted and CPU is HD6120 and Panel Mode and Direct
        --!     Memory Op with PDF in any state (two cases of CTRLFF).
        --! #.  MEMSEL asserted and CPU is HD6120 and Panel Mode and Indirect
        --!     Memory Op with PDF asserted (two cases of CTRLFF).
        --!

        lxparOP <= '1' when ((memselOP = '1' and swCPU  = swHD6120 and CTRLFF = '0' and ctrlffOP  = ctrlffopSET and datafOP = '0') or
                             (memselOP = '1' and swCPU  = swHD6120 and CTRLFF = '1' and ctrlffOP /= ctrlffopCLR and datafOP = '0') or
                             (memselOP = '1' and swCPU  = swHD6120 and CTRLFF = '0' and ctrlffOP  = ctrlffopSET and datafOP = '1' and PDF = '1') or
                             (memselOP = '1' and swCPU  = swHD6120 and CTRLFF = '1' and ctrlffOP /= ctrlffopCLR and datafOP = '1' and PDF = '1')) else
                   '0';


        --!
        --! LXMAR is generated for normal memory accesses.  It is asserted when:
        --! #.  MEMSEL asserted and CPU is HD6120 and Panel Mode and Indirect
        --!     Memory Op with PDF negated (two cases of CRTLFF).
        --! #.  MEMSEL asserted and CPU is HD6120 and Normal Mode (two cases of
        --!     CTRLFF).
        --! #.  MEMSEL asserted and not HD6120.
        --!

        lxmarOP <= '1' when ((memselOP = '1' and swCPU  = swHD6120 and CTRLFF = '0' and ctrlffOP  = ctrlffopSET and datafOP = '1' and PDF = '0') or
                             (memselOP = '1' and swCPU  = swHD6120 and CTRLFF = '1' and ctrlffOP /= ctrlffopCLR and datafOP = '1' and PDF = '0') or
                             (memselOP = '1' and swCPU  = swHD6120 and CTRLFF = '0' and ctrlffOP /= ctrlffopSET) or
                             (memselOP = '1' and swCPU  = swHD6120 and CTRLFF = '1' and ctrlffOP  = ctrlffopCLR) or
                             (memselOP = '1' and swCPU /= swHD6120)) else
                   '0';

        --!
        --! Wait for Bus ACK on:
        --! #.  DMA access
        --! #.  Memory accesses
        --! #.  Reads to devices
        --! #.  Writes to devices
        --!

        waitfOP <= '1' when ((memselOP = '1') or
                             (lxdarOP = '1' and rdOP = '1') or
                             (lxdarOP = '1' and wrOP = '1')) else
                   '0';

    end block;

    --
    --! DMA Request.
    --! Only start DMA cycle when MEM cycle is unused.
    --

    DMAREQ : process(sys)
    begin
        if sys.rst = '1' then
            dmagnt <= '0';
        elsif rising_edge(sys.clk) then
            if dev.dma.req = '1' then
                if memselOP = '0' then
                    dmagnt <= '1';
                end if;
            else
                dmagnt <= '0';
            end if;
        end if;
    end process DMAREQ;

    --
    --! State Machine
    --! The state only changes when properly ack'd and when not doing DMA.
    --

    CURR_STATE : process(sys)
        variable lastdma : std_logic;
        -- synthesis translate_off
        variable LIN : line;
        -- synthesis translate_on
    begin
        if sys.rst = '1' then
            ioclrb  <= '1';
            wrb     <= '0';
            rdb     <= '0';
            ifetchb <= '0';
            datafb  <= '0';
            lxdarb  <= '0';
            lxmarb  <= '0';
            lxparb  <= '0';
            memselb <= '0';
            intgntb <= '0';
            waitfb  <= '0';
            lastdma := '0';
            state   <= stateReset;
        elsif rising_edge(sys.clk) then
            if dmagnt = '1' and memselOP = '1' then
                null;
            else
                if waitfb = '0' or dev.ack = '1' then
                    ioclrb  <= ioclrOP;
                    wrb     <= wrOP;
                    rdb     <= rdOP;
                    ifetchb <= ifetchOP;
                    datafb  <= datafOP;
                    lxdarb  <= lxdarOP;
                    lxmarb  <= lxmarOP;
                    lxparb  <= lxparOP;
                    memselb <= memselOP;
                    intgntb <= intgntOP;
                    waitfb  <= waitfOP;
                    state   <= nextState;
                end if;
            end if;

-- synthesis translate_off

            if dmagnt = '1' and lastdma = '0' then
                assert false report "-------------> DMA Asserted <------------" severity note;
            elsif dmagnt = '0' and lastdma = '1' then
                assert false report "-------------> DMA Negated <------------" severity note;
            end if;
            lastdma := dmagnt;

            case xmaOP is
                when xmaopIF =>
                    if datafOP = '1' then
                        assert false report "Bus Monitor: XMA <- IF, but datafOP <- '1' " severity note;
                    end if;
                when xmaopDF =>
                    if datafOP = '0' then
                        assert false report "Bus Monitor: XMA <- DF, but datafOP <- '0' " severity note;
                    end if;
                when others =>
                    if memselOP = '1' then
                        assert false report "Bus Monitor: XMA <- NOP, but memselOP <- '1' " severity note;
                    end if;
             end case;

-- synthesis translate_on

        end if;
    end process CURR_STATE;

--    oops <= '1' when ((xmaOP  = xmaopIF and datafOP  = '1') or
--                      (xmaOP  = xmaopDF and datafOP  = '0') or
--                      (xmaOP /= xmaopIF and memselOP = '1') or
--                      (xmaOP /= xmaopDF and memselOP = '1')) else '0';


    oops <= '1' when ((busOP = busopRESET       and ioclrOP   =      '0') or            -- IOCLR should be set

                      (busOP = busopIOCLR       and ioclrOP  =       '0') or            -- IOCLR should be set
                      (busOP = busopIOCLR       and lxdarOP  =       '0') or            -- LXDAR should be set
                      (busOP = busopIOCLR       and datafOP  =       '0') or            -- DATAF should be set

                      (busOP = busopFETCHaddr   and xmaOP    /=  xmaopIF) or
                      (busOP = busopFETCHaddr   and ifetchOP  =      '0') or
                      (busOP = busopFETCHaddr   and memselOP  =      '0') or

                      (busOP = busopFETCHdata   and xmaOP    /=  xmaopIF) or
                      (busOP = busopFETCHdata   and ifetchOP  =      '0') or
                      (busOP = busopFETCHdata   and memselOP  =      '0') or
                      (busOP = busopFETCHdata   and rdOP      =      '0') or

                      (busOP = busopWRIB        and xmaOP    /=  xmaopIB) or
                      (busOP = busopWRIB        and memselOP  =      '0') or
                      (busOP = busopWRIB        and wrOP      =      '0') or

                      (busOP = busopRDIBaddr    and xmaOP    /=  xmaopIB) or
                      (busOP = busopRDIBaddr    and memselOP  =      '0') or

                      (busOP = busopRDIBdata    and xmaOP    /=  xmaopIB) or
                      (busOP = busopRDIBdata    and memselOP  =      '0') or
                      (busOP = busopRDIBdata    and rdOP      =      '0') or

                      (busOP = busopWRIF        and xmaOP    /=  xmaopIF) or
                      (busOP = busopWRIF        and memselOP  =      '0') or
                      (busOP = busopWRIF        and wrOP      =      '0') or

                      (busOP = busopRDIFaddr    and xmaOP    /=  xmaopIF) or
                      (busOP = busopRDIFaddr    and memselOP  =      '0') or

                      (busOP = busopRDIFdata    and xmaOP    /=  xmaopIF) or
                      (busOP = busopRDIFdata    and memselOP  =      '0') or
                      (busOP = busopRDIFdata    and rdOP      =      '0') or

                      (busOP = busopWRDF        and xmaOP    /=  xmaopDF) or
                      (busOP = busopWRDF        and memselOP  =      '0') or
                      (busOP = busopRDDFaddr    and datafOP   =      '0') or
                      (busOP = busopWRDF        and wrOP      =      '0') or

                      (busOP = busopRDDFaddr    and xmaOP    /=  xmaopDF) or
                      (busOP = busopRDDFaddr    and memselOP  =      '0') or
                      (busOP = busopRDDFaddr    and datafOP   =      '0') or

                      (busOP = busopRDDFdata    and xmaOP    /=  xmaopDF) or
                      (busOP = busopRDDFdata    and memselOP  =      '0') or
                      (busOP = busopRDDFdata    and datafOP   =      '0') or
                      (busOP = busopRDDFdata    and rdOP      =      '0') or

                      (busOP = busopWRZF        and xmaOP    /= xmaopCLR) or
                      (busOP = busopWRZF        and memselOP   =     '0') or
                      (busOP = busopWRZF        and wrOP       =     '0') or

                      (busOP = busopRDZFaddr    and xmaOP    /= xmaopCLR) or
                      (busOP = busopRDZFaddr    and memselOP  =      '0') or

                      (busOP = busopRDZFdata    and xmaOP    /= xmaopCLR) or
                      (busOP = busopRDZFdata    and memselOP  =      '0') or
                      (busOP = busopRDZFdata    and rdOP      =      '0') or

                      (busOP = busopWRIOT       and datafOP  =       '0') or
                      (busOP = busopWRIOT       and lxdarOP  =       '0') or
                      (busOP = busopWRIOT       and wrOP     =       '0') or

                      (busOP = busopRDIOT       and datafOP  =       '0') or
                      (busOP = busopRDIOT       and lxdarOP  =       '0') or
                      (busOP = busopRDIOT       and rdOP     =       '0')) else '0';


    --! PANEL:
    --! Externally visable (front panel) register state is only updated at
    --! certain times in the instruction cycle.
    --

    PANEL : process(sys)
        variable CPC : addr_t;
    begin
        if sys.rst = '1' then
            cpu.regs.PC  <= (others => '0');
            cpu.regs.AC  <= (others => '0');
            cpu.regs.IR  <= (others => '0');
            cpu.regs.MQ  <= (others => '0');
            cpu.regs.ST  <= (others => '0');
            cpu.regs.SC  <= (others => '0');
            cpu.regs.MD  <= (others => '0');
            cpu.regs.MA  <= (others => '0');
            cpu.regs.XMA <= (others => '0');
            CPC          := (others => '0');
        elsif rising_edge(sys.clk) then

            --
            -- Handle reads are writes
            --

            if lxmarb = '1' then
                if rdb = '1' then
                    cpu.regs.MD <= MD;
                elsif wrb = '1' then
                    cpu.regs.MD <= MB;
                end if;
                cpu.regs.MA  <= MA;
                cpu.regs.XMA <= XMA;
            end if;

            --
            -- State-based updates
            --

            case state is

                --
                -- Instruction Fetch
                --

                when stateFetchAddr =>
                    CPC := PC;

                --
                -- State Halt Done
                --

                when stateHaltDone =>
                    cpu.regs.PC <= PC;
                    cpu.regs.AC <= AC;
                    cpu.regs.IR <= IR;
                    cpu.regs.MA <= MA;
                    cpu.regs.MQ <= MQ;
                    cpu.regs.ST <= L & GTF & IRQ & II & ID & UF & INF & DF;
                    cpu.regs.SC <= "0000000" & SC;

                --
                -- Last state of instruction
                --

                when stateDone =>
                    cpu.regs.PC <= PC;
                    cpu.regs.AC <= AC;
                    cpu.regs.IR <= IR;
                    cpu.regs.MQ <= MQ;
                    cpu.regs.ST <= L & GTF & IRQ & II & ID & UF & INF & DF;
                    cpu.regs.SC <= "0000000" & SC;
                    dumpState(CPC);

                --
                -- Anything else?
                --

                when others =>
                    null;
            end case;
        end if;
    end process PANEL;

    --!
    --! DMA Bus Switch
    --!

    DMA : process(dmagnt, dev, dev.dma, rdb, wrb, ifetchb, lxmarb, lxparb,
            lxdarb, memselb, datafb, MA, MB, XMA)
    begin
        if dmagnt = '1' then
            cpu.buss.rd     <= dev.dma.rd;
            cpu.buss.wr     <= dev.dma.wr;
            cpu.buss.ifetch <= '0';
            cpu.buss.dataf  <= '0';
            cpu.buss.lxmar  <= dev.dma.lxmar;
            cpu.buss.lxpar  <= dev.dma.lxpar;
            cpu.buss.lxdar  <= '0';
            cpu.buss.memsel <= dev.dma.memsel;
            cpu.buss.addr   <= dev.dma.addr;
            cpu.buss.eaddr  <= dev.dma.eaddr;
            cpu.buss.data   <= dev.data;
        else
            cpu.buss.rd     <= rdb;
            cpu.buss.wr     <= wrb;
            cpu.buss.ifetch <= ifetchb;
            cpu.buss.dataf  <= datafb;
            cpu.buss.lxmar  <= lxmarb;
            cpu.buss.lxpar  <= lxparb;
            cpu.buss.lxdar  <= lxdarb;
            cpu.buss.memsel <= memselb;
            cpu.buss.addr   <= MA;
            cpu.buss.eaddr  <= XMA;
            cpu.buss.data   <= MB;
        end if;
    end process DMA;

    --
    --! Data Latch
    --! \note
    --!      For now, this processes should infer a latch for the MD
    --!     xs Register.  This is intentional.
    --

    REG_MD : process(sys.rst, rdb, dev.data, MD)
    begin
        if sys.rst = '1' then
            MD <= (others => '0');
        elsif rdb = '1' then
            MD <= dev.data;
        else
            MD <= MD;
        end if;
    end process REG_MD;

    --!
    --! CPU combinational outputs
    --!

    cpu.buss.ioclr  <= ioclrb;
    cpu.buss.intgnt <= intgntb;
    cpu.buss.dmagnt <= dmagnt;
    cpu.run         <= '0' when ((state = stateReset            ) or
                                 (state = stateInit             ) or
                                 (state = stateHalt             ) or
                                 (state = stateContinue         ) or
                                 (state = stateLoadADDR         ) or
                                 (state = stateLoadEXTD         ) or
                                 (state = stateClear            ) or
                                 (state = stateDepositWriteData ) or
                                 (state = stateDeposit          ) or
                                 (state = stateExamine          ) or
                                 (state = stateExamineReadAddr  ) or
                                 (state = stateExamineReadData  ) or
                                 (state = stateHaltDone         ) or
                                 (state = stateLALA             )) else
                       '1';

end rtl;
