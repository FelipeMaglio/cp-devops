package br.com.dimdim.controller;

import br.com.dimdim.model.Transacao;
import br.com.dimdim.repository.ClienteRepository;
import br.com.dimdim.repository.TransacaoRepository;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api")
public class TransacaoController {

    private final TransacaoRepository transacaoRepo;
    private final ClienteRepository clienteRepo;

    public TransacaoController(TransacaoRepository transacaoRepo, ClienteRepository clienteRepo) {
        this.transacaoRepo = transacaoRepo;
        this.clienteRepo = clienteRepo;
    }

    @GetMapping("/transacoes")
    public List<Transacao> listarTodas() {
        return transacaoRepo.findAll();
    }

    @GetMapping("/transacoes/{id}")
    public ResponseEntity<Transacao> buscar(@PathVariable Long id) {
        return transacaoRepo.findById(id).map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @GetMapping("/clientes/{idCliente}/transacoes")
    public ResponseEntity<List<Transacao>> listarPorCliente(@PathVariable Long idCliente) {
        if (!clienteRepo.existsById(idCliente)) return ResponseEntity.notFound().build();
        return ResponseEntity.ok(transacaoRepo.findByClienteId(idCliente));
    }

    @PostMapping("/clientes/{idCliente}/transacoes")
    public ResponseEntity<Transacao> criar(@PathVariable Long idCliente, @Valid @RequestBody Transacao t) {
        return clienteRepo.findById(idCliente).map(cliente -> {
            t.setId(null);
            t.setCliente(cliente);
            return ResponseEntity.status(HttpStatus.CREATED).body(transacaoRepo.save(t));
        }).orElse(ResponseEntity.notFound().build());
    }

    @PutMapping("/transacoes/{id}")
    public ResponseEntity<Transacao> atualizar(@PathVariable Long id, @Valid @RequestBody Transacao dados) {
        return transacaoRepo.findById(id).map(t -> {
            t.setTipo(dados.getTipo());
            t.setValor(dados.getValor());
            return ResponseEntity.ok(transacaoRepo.save(t));
        }).orElse(ResponseEntity.notFound().build());
    }

    @DeleteMapping("/transacoes/{id}")
    public ResponseEntity<Void> excluir(@PathVariable Long id) {
        if (!transacaoRepo.existsById(id)) return ResponseEntity.notFound().build();
        transacaoRepo.deleteById(id);
        return ResponseEntity.noContent().build();
    }
}
