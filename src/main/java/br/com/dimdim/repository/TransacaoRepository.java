package br.com.dimdim.repository;

import br.com.dimdim.model.Transacao;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface TransacaoRepository extends JpaRepository<Transacao, Long> {
    List<Transacao> findByClienteId(Long idCliente);
}
