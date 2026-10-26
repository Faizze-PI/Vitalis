import java.util.Map;

public final class TransferCoverageGateTest {
    public static void main(String[] args) throws Exception {
        Map<String, Integer> required = Map.of("Recovery.java", 90);
        String prefix = "<report name='test'><package name='com/vitalis/vitalis_app/transfer'>";
        String suffix = "</package></report>";
        String good = prefix + "<sourcefile name='Recovery.java'><counter type='LINE' missed='1' covered='9'/></sourcefile>" + suffix;
        if (!TransferCoverageGate.evaluate(good, required).isEmpty()) throw new AssertionError("Valid boundary rejected");
        String[] invalid = {
            prefix + suffix,
            good.replace("covered='9'", "covered='8'"),
            good.replace("missed='1' covered='9'", "missed='0' covered='0'"),
            good.replace("missed='1'", "missed='-1'"),
            good.replace("covered='9'", "covered='oops'"),
            good.replace("</sourcefile>", "<counter type='LINE' missed='1' covered='9'/></sourcefile>"),
            good.replace("</package>", "<sourcefile name='Recovery.java'><counter type='LINE' missed='0' covered='10'/></sourcefile></package>"),
            good.replace("com/vitalis/vitalis_app/transfer", "unrelated"),
            good.replace("</report>", ""),
            "<!DOCTYPE report [<!ENTITY x SYSTEM 'file:///not-authorized'>]>" + good
        };
        for (int index = 0; index < invalid.length; index++) {
            if (TransferCoverageGate.evaluate(invalid[index], required).isEmpty()) {
                throw new AssertionError("Invalid coverage accepted: " + index);
            }
        }
        System.out.println("Transfer coverage gate: valid boundary and 10 invalid reports checked");
    }
}
