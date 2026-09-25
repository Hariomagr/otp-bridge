// Mirror of the Android Crypto logic, in plain Java, to prove interop with the
// Node/Swift wire format before building the full app.
// argv: <keyB64> <room> <nonceB64> <ctB64>  -> prints decrypted plaintext.
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.util.Base64;

public class CryptoInterop {
    public static void main(String[] args) throws Exception {
        byte[] key   = Base64.getDecoder().decode(args[0]);
        String room  = args[1];
        byte[] nonce = Base64.getDecoder().decode(args[2]);
        byte[] ct    = Base64.getDecoder().decode(args[3]); // ciphertext||tag

        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE,
                new SecretKeySpec(key, "AES"),
                new GCMParameterSpec(128, nonce)); // 128-bit tag
        cipher.updateAAD(room.getBytes(StandardCharsets.UTF_8));
        byte[] plaintext = cipher.doFinal(ct);
        System.out.print(new String(plaintext, StandardCharsets.UTF_8));
    }
}
